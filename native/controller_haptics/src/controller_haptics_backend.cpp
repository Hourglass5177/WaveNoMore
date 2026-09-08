#include "controller_haptics_backend.h"
#include <godot_cpp/core/class_db.hpp>
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <deque>
#include <functional>
#include <future>
#include <limits>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <vector>

namespace {
using Clock = std::chrono::steady_clock;
constexpr double TAU = 6.28318530717958647692;
constexpr Uint32 LEASE_MS = 60000;
constexpr auto RENEW_INTERVAL = std::chrono::seconds(20);
// Priority: two implementations of dual strength, then mono periodic, then simple rumble.
enum Candidate { JOYSTICK_RUMBLE, LEFT_RIGHT_EFFECT, SINE_EFFECT, SIMPLE_RUMBLE, CANDIDATE_COUNT };
const char *BACKEND_NAMES[] = { "sdl_joystick_rumble", "sdl_haptic_leftright", "sdl_haptic_sine", "sdl_simple_rumble" };

struct Request {
	double left_hz = 0.0, left_strength = 0.0, right_hz = 0.0, right_strength = 0.0;
	double frequency_multiplier = 1.0, strength_multiplier = 1.0;
	bool operator==(const Request &other) const {
		return left_hz == other.left_hz && left_strength == other.left_strength &&
			right_hz == other.right_hz && right_strength == other.right_strength &&
			frequency_multiplier == other.frequency_multiplier && strength_multiplier == other.strength_multiplier;
	}
	bool valid() const {
		return std::isfinite(left_hz) && std::isfinite(right_hz) &&
			std::isfinite(left_strength) && std::isfinite(right_strength) &&
			std::isfinite(frequency_multiplier) && std::isfinite(strength_multiplier) &&
			left_hz >= 0.0 && right_hz >= 0.0 && left_strength >= 0.0 && left_strength <= 1.0 &&
			right_strength >= 0.0 && right_strength <= 1.0 && frequency_multiplier >= 0.0 && strength_multiplier >= 0.0 &&
			(left_strength == 0.0 || left_hz > 0.0) && (right_strength == 0.0 || right_hz > 0.0) &&
			std::isfinite(left_hz * frequency_multiplier) && std::isfinite(right_hz * frequency_multiplier);
	}
};

struct Capabilities {
	std::array<bool, CANDIDATE_COUNT> supported{};
	std::array<bool, CANDIDATE_COUNT> rejected{};
	bool raw_custom_effect = false;
};

struct Submitted {
	double left_strength = 0.0, right_strength = 0.0, mono_strength = 0.0;
	double frequency_hz = -1.0, phase_rad = -1.0;
	int period_ms = 0;
	std::string phase_side;
};

struct Status {
	int64_t device_id = -1;
	bool has_request = false, running = false, accepted = false;
	Request request;
	Submitted submitted;
	std::array<double, 2> phase{};
	std::string mode = "unbound", backend, reason, error;
	Capabilities capabilities;
};

struct DeviceInfo {
	SDL_JoystickID id;
	std::string name, path;
	Uint16 vendor, product;
};

// A session is used only on the shared worker thread. No Godot Objects or Variants live here.
struct HapticState {
	SDL_Joystick *joystick = nullptr;
	SDL_Haptic *haptic = nullptr;
	SDL_HapticEffectID effect_id = -1;
	int candidate = -1;
	bool simple_initialized = false;
	Status status;
	Clock::time_point phase_time = Clock::now(), renew_at = Clock::now();

	void advance_phase(Clock::time_point now) {
		if (status.has_request) {
			const double elapsed = std::chrono::duration<double>(now - phase_time).count();
			status.phase[0] += TAU * status.request.left_hz * elapsed;
			status.phase[1] += TAU * status.request.right_hz * elapsed;
		}
		phase_time = now;
	}

	// Stop only effects owned by this session, never all force-feedback effects on the device.
	void stop_physical() {
		if (effect_id >= 0 && haptic) {
			SDL_StopHapticEffect(haptic, effect_id);
			SDL_DestroyHapticEffect(haptic, effect_id);
			effect_id = -1;
		}
		if (candidate == JOYSTICK_RUMBLE && joystick) SDL_RumbleJoystick(joystick, 0, 0, 0);
		if (candidate == SIMPLE_RUMBLE && haptic && simple_initialized) SDL_StopHapticRumble(haptic);
		candidate = -1;
		status.running = false;
	}

	void stop(const std::string &reason = "stopped") {
		stop_physical();
		status.request = {};
		status.submitted = {};
		status.phase = {};
		status.has_request = false;
		status.accepted = false;
		status.mode = joystick ? "idle" : "unbound";
		status.backend.clear();
		status.reason = reason;
		status.error.clear();
		phase_time = Clock::now();
	}

	void close(const std::string &reason = "unbound") {
		stop(reason);
		if (haptic) SDL_CloseHaptic(haptic);
		if (joystick) SDL_CloseJoystick(joystick);
		haptic = nullptr;
		joystick = nullptr;
		simple_initialized = false;
		status.device_id = -1;
		status.capabilities = {};
		status.mode = "unbound";
	}

	bool connected() {
		if (joystick && !SDL_JoystickConnected(joystick)) close("device_disconnected");
		return joystick != nullptr;
	}

	// Query support only. No effect is created or played during enumeration/binding.
	void detect() {
		status.capabilities = {};
		auto &caps = status.capabilities;
		caps.supported[JOYSTICK_RUMBLE] = SDL_GetBooleanProperty(
			SDL_GetJoystickProperties(joystick), SDL_PROP_JOYSTICK_CAP_RUMBLE_BOOLEAN, false);
		if (!SDL_IsJoystickHaptic(joystick)) return;
		haptic = SDL_OpenHapticFromJoystick(joystick);
		if (!haptic) return;
		const Uint32 features = SDL_GetHapticFeatures(haptic);
		SDL_HapticEffect probe{};
		probe.leftright.type = SDL_HAPTIC_LEFTRIGHT;
		probe.leftright.length = LEASE_MS;
		caps.supported[LEFT_RIGHT_EFFECT] = (features & SDL_HAPTIC_LEFTRIGHT) && SDL_HapticEffectSupported(haptic, &probe);
		probe = {};
		probe.periodic.type = SDL_HAPTIC_SINE;
		probe.periodic.direction.type = SDL_HAPTIC_CARTESIAN;
		probe.periodic.direction.dir[0] = 1;
		probe.periodic.length = LEASE_MS;
		probe.periodic.period = 10;
		caps.supported[SINE_EFFECT] = (features & SDL_HAPTIC_SINE) && SDL_HapticEffectSupported(haptic, &probe);
		caps.supported[SIMPLE_RUMBLE] = SDL_HapticRumbleSupported(haptic);
		// Raw CUSTOM does not prove continuous streaming, nor do axes prove left/right motor mapping.
		caps.raw_custom_effect = (features & SDL_HAPTIC_CUSTOM) != 0;
	}

	bool play_effect(const SDL_HapticEffect &effect) {
		if (effect_id < 0) {
			effect_id = SDL_CreateHapticEffect(haptic, &effect);
			if (effect_id < 0) return false;
		} else if (!SDL_UpdateHapticEffect(haptic, effect_id, &effect)) {
			return false;
		}
		return SDL_RunHapticEffect(haptic, effect_id, 1);
	}

	bool submit_candidate(int index) {
		if (candidate != index) stop_physical();
		candidate = index;
		const Request &r = status.request;
		const double left = std::clamp(r.left_strength * r.strength_multiplier, 0.0, 1.0);
		const double right = std::clamp(r.right_strength * r.strength_multiplier, 0.0, 1.0);
		Submitted submitted;
		bool success = false;
		SDL_HapticEffect effect{};
		if (index == JOYSTICK_RUMBLE || index == LEFT_RIGHT_EFFECT) {
			const Uint16 large = static_cast<Uint16>(std::lround(left * 65535.0));
			const Uint16 small = static_cast<Uint16>(std::lround(right * 65535.0));
			submitted.left_strength = large / 65535.0;
			submitted.right_strength = small / 65535.0;
			if (index == JOYSTICK_RUMBLE) {
				success = SDL_RumbleJoystick(joystick, large, small, LEASE_MS);
			} else {
				effect.leftright.type = SDL_HAPTIC_LEFTRIGHT;
				effect.leftright.length = LEASE_MS;
				effect.leftright.large_magnitude = large;
				effect.leftright.small_magnitude = small;
				success = play_effect(effect);
			}
		} else if (index == SINE_EFFECT) {
			// Muted sides do not compete for the maximum frequency. Ties use the left reference.
			const double left_hz = left > 0.0 ? r.left_hz : 0.0;
			const double right_hz = right > 0.0 ? r.right_hz : 0.0;
			const int side = right_hz > left_hz ? 1 : 0;
			const double scaled_hz = std::max(left_hz, right_hz) * r.frequency_multiplier;
			if (scaled_hz == 0.0) {
				stop_physical();
				status.submitted = {};
				status.mode = "silent";
				status.backend = BACKEND_NAMES[index];
				status.reason = "zero_frequency_multiplier";
				return true;
			}
			const Uint16 period = static_cast<Uint16>(std::lround(std::clamp(1000.0 / scaled_hz, 1.0, 65535.0)));
			double phase = std::fmod(status.phase[side] * r.frequency_multiplier, TAU);
			if (phase < 0.0) phase += TAU;
			const Uint16 phase_units = static_cast<Uint16>(std::lround(phase / TAU * 36000.0) % 36000);
			const Sint16 magnitude = static_cast<Sint16>(std::lround(std::max(left, right) * 32767.0));
			effect.periodic.type = SDL_HAPTIC_SINE;
			effect.periodic.direction.type = SDL_HAPTIC_CARTESIAN;
			effect.periodic.direction.dir[0] = 1;
			effect.periodic.length = LEASE_MS;
			effect.periodic.period = period;
			effect.periodic.magnitude = magnitude;
			effect.periodic.phase = phase_units;
			submitted.frequency_hz = 1000.0 / period;
			submitted.period_ms = period;
			submitted.phase_rad = phase_units / 36000.0 * TAU;
			submitted.phase_side = side == 0 ? "left" : "right";
			submitted.mono_strength = magnitude / 32767.0;
			success = play_effect(effect);
		} else {
			if (!simple_initialized) simple_initialized = SDL_InitHapticRumble(haptic);
			submitted.mono_strength = std::max(left, right);
			success = simple_initialized && SDL_PlayHapticRumble(haptic, static_cast<float>(submitted.mono_strength), LEASE_MS);
		}
		if (success) {
			status.submitted = submitted;
			status.running = true;
			status.mode = index <= LEFT_RIGHT_EFFECT ? "dual_strength" : index == SINE_EFFECT ? "mono_periodic" : "mono_strength";
			status.backend = BACKEND_NAMES[index];
			status.reason = index <= LEFT_RIGHT_EFFECT ? "independent_frequency_unavailable" :
				index == SINE_EFFECT ? "independent_motors_and_continuous_mix_unavailable" : "frequency_control_unavailable";
			renew_at = Clock::now() + RENEW_INTERVAL;
		}
		return success;
	}

	bool apply() {
		if (!connected()) {
			status.error = "No connected device is bound.";
			return false;
		}
		advance_phase(Clock::now());
		if (status.request.strength_multiplier == 0.0 ||
			(status.request.left_strength == 0.0 && status.request.right_strength == 0.0)) {
			stop_physical();
			status.submitted = {};
			status.mode = "silent";
			status.backend.clear();
			status.reason = "zero_strength";
			status.accepted = true;
			return true;
		}
		for (int index = 0; index < CANDIDATE_COUNT; ++index) {
			if (!status.capabilities.supported[index] || status.capabilities.rejected[index]) continue;
			if (submit_candidate(index)) {
				status.accepted = true;
				return true;
			}
			status.error = std::string(BACKEND_NAMES[index]) + ": " + SDL_GetError();
			status.capabilities.rejected[index] = true;
			stop_physical();
		}
		status.accepted = false;
		status.mode = "unsupported";
		status.backend.clear();
		status.submitted = {};
		status.reason = "no_usable_output_backend";
		return false;
	}

	bool set_output(const Request &request) {
		if (!request.valid()) {
			status.error = "Invalid target: finite nonnegative Hz/gains and strengths in [0,1] required; an active side needs positive Hz.";
			return false;
		}
		if (!connected()) {
			status.error = "No connected device is bound.";
			return false;
		}
		advance_phase(Clock::now());
		if (status.has_request && status.accepted && request == status.request) return true;
		status.request = request;
		status.has_request = true;
		status.error.clear();
		return apply();
	}

	void tick() {
		if (!connected()) return;
		if (status.running && Clock::now() >= renew_at) apply();
	}
};

// One private SDL thread owns initialization, handles, calls and renewal for every module instance.
// Main-thread methods send synchronous jobs; only plain C++ values cross this boundary.
struct HapticRuntime {
	std::mutex mutex;
	std::condition_variable wake;
	std::deque<std::function<void()>> jobs;
	bool quitting = false;
	bool initialized = false;
	std::string error;
	std::set<HapticState *> sessions;
	std::thread worker;

	HapticRuntime() : worker([this] { run(); }) {}
	~HapticRuntime() {
		{
			std::lock_guard<std::mutex> lock(mutex);
			quitting = true;
		}
		wake.notify_one();
		worker.join();
	}
	template <class F> auto call(F function) -> decltype(function()) {
		using Result = decltype(function());
		auto task = std::make_shared<std::packaged_task<Result()>>(std::move(function));
		auto future = task->get_future();
		{
			std::lock_guard<std::mutex> lock(mutex);
			jobs.emplace_back([task] { (*task)(); });
		}
		wake.notify_one();
		return future.get();
	}
	bool initialize() {
		if (initialized) return true;
		SDL_SetMainReady();
		if (!SDL_InitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_HAPTIC)) {
			error = SDL_GetError();
			return false;
		}
		SDL_SetJoystickEventsEnabled(false);
		initialized = true;
		return true;
	}
	void run() {
		while (true) {
			std::deque<std::function<void()>> current;
			{
				std::unique_lock<std::mutex> lock(mutex);
				wake.wait_for(lock, std::chrono::milliseconds(250), [this] { return quitting || !jobs.empty(); });
				if (quitting && jobs.empty()) break;
				current.swap(jobs);
			}
			for (auto &job : current) job();
			if (initialized) {
				SDL_UpdateJoysticks();
				for (auto *session : sessions) session->tick();
			}
		}
		if (initialized) SDL_QuitSubSystem(SDL_INIT_HAPTIC | SDL_INIT_JOYSTICK);
	}
};

std::shared_ptr<HapticRuntime> acquire_runtime() {
	static std::mutex mutex;
	static std::weak_ptr<HapticRuntime> shared;
	std::lock_guard<std::mutex> lock(mutex);
	auto runtime = shared.lock();
	if (!runtime) {
		runtime = std::make_shared<HapticRuntime>();
		shared = runtime;
	}
	return runtime;
}

godot::Dictionary capabilities_dictionary(const Status &s) {
	godot::Dictionary result;
	result["device_id"] = s.device_id;
	result["dual_independent_frequency"] = false;
	result["continuous_mixed_waveform"] = false;
	result["raw_custom_effect_reported"] = s.capabilities.raw_custom_effect;
	result["advanced_unavailable_reason"] = "Generic SDL effects do not prove independent actuator frequency control or continuous mixed waveform playback.";
	result["dual_strength"] = (s.capabilities.supported[JOYSTICK_RUMBLE] && !s.capabilities.rejected[JOYSTICK_RUMBLE]) ||
		(s.capabilities.supported[LEFT_RIGHT_EFFECT] && !s.capabilities.rejected[LEFT_RIGHT_EFFECT]);
	result["mono_periodic"] = s.capabilities.supported[SINE_EFFECT] && !s.capabilities.rejected[SINE_EFFECT];
	result["mono_strength"] = s.capabilities.supported[SIMPLE_RUMBLE] && !s.capabilities.rejected[SIMPLE_RUMBLE];
	godot::Array supported, rejected;
	for (int index = 0; index < CANDIDATE_COUNT; ++index) {
		if (s.capabilities.supported[index]) supported.append(BACKEND_NAMES[index]);
		if (s.capabilities.rejected[index]) rejected.append(BACKEND_NAMES[index]);
	}
	result["reported_backends"] = supported;
	result["rejected_backends"] = rejected;
	return result;
}
}

namespace godot {
struct ControllerHapticsBackend::Impl {
	HapticState state;
	std::shared_ptr<HapticRuntime> runtime;
	void ensure_runtime() {
		if (runtime) return;
		runtime = acquire_runtime();
		runtime->call([this] { runtime->sessions.insert(&state); });
	}
	~Impl() {
		if (runtime) runtime->call([this] { state.close(); runtime->sessions.erase(&state); });
	}
	Status snapshot() {
		if (!runtime) return state.status;
		return runtime->call([this] { state.connected(); state.advance_phase(Clock::now()); return state.status; });
	}
};

ControllerHapticsBackend::ControllerHapticsBackend() : impl(std::make_unique<Impl>()) {}
ControllerHapticsBackend::~ControllerHapticsBackend() = default;

void ControllerHapticsBackend::_bind_methods() {
	ClassDB::bind_method(D_METHOD("list_devices"), &ControllerHapticsBackend::list_devices);
	ClassDB::bind_method(D_METHOD("bind_device", "device_id"), &ControllerHapticsBackend::bind_device);
	ClassDB::bind_method(D_METHOD("get_capabilities"), &ControllerHapticsBackend::get_capabilities);
	ClassDB::bind_method(D_METHOD("set_output", "left_hz", "left_strength", "right_hz", "right_strength", "frequency_multiplier", "strength_multiplier"), &ControllerHapticsBackend::set_output);
	ClassDB::bind_method(D_METHOD("set_phase_reference", "left_phase_rad", "right_phase_rad"), &ControllerHapticsBackend::set_phase_reference);
	ClassDB::bind_method(D_METHOD("stop"), &ControllerHapticsBackend::stop);
	ClassDB::bind_method(D_METHOD("unbind_device"), &ControllerHapticsBackend::unbind_device);
	ClassDB::bind_method(D_METHOD("get_output_status"), &ControllerHapticsBackend::get_output_status);
}

TypedArray<Dictionary> ControllerHapticsBackend::list_devices() {
	impl->ensure_runtime();
	auto devices = impl->runtime->call([this] {
		std::vector<DeviceInfo> result;
		if (!impl->runtime->initialize()) {
			impl->state.status.error = impl->runtime->error;
			return result;
		}
		SDL_UpdateJoysticks();
		int count = 0;
		SDL_JoystickID *ids = SDL_GetJoysticks(&count);
		for (int index = 0; ids && index < count; ++index) {
			const char *name = SDL_GetJoystickNameForID(ids[index]);
			const char *path = SDL_GetJoystickPathForID(ids[index]);
			result.push_back({ ids[index], name ? name : "", path ? path : "",
				SDL_GetJoystickVendorForID(ids[index]), SDL_GetJoystickProductForID(ids[index]) });
		}
		SDL_free(ids);
		return result;
	});
	TypedArray<Dictionary> result;
	for (const auto &device : devices) {
		Dictionary data;
		data["device_id"] = int64_t(device.id);
		data["name"] = String::utf8(device.name.c_str());
		data["path"] = String::utf8(device.path.c_str());
		data["vendor_id"] = int64_t(device.vendor);
		data["product_id"] = int64_t(device.product);
		result.append(data);
	}
	return result;
}

bool ControllerHapticsBackend::bind_device(int64_t id) {
	impl->ensure_runtime();
	return impl->runtime->call([this, id] {
		auto &state = impl->state;
		state.close();
		if (id <= 0 || id > std::numeric_limits<SDL_JoystickID>::max()) {
			state.status.error = "Use a device_id returned by list_devices(), not a Godot Input ID.";
			return false;
		}
		if (!impl->runtime->initialize()) {
			state.status.error = impl->runtime->error;
			return false;
		}
		SDL_UpdateJoysticks();
		for (auto *other : impl->runtime->sessions) {
			if (other != &state && other->connected() && other->status.device_id == id) {
				state.status.error = "This device is already bound by another ControllerHaptics instance.";
				return false;
			}
		}
		state.joystick = SDL_OpenJoystick(static_cast<SDL_JoystickID>(id));
		if (!state.joystick) {
			state.status.error = SDL_GetError();
			return false;
		}
		state.status.device_id = id;
		state.status.mode = "idle";
		state.status.reason = "bound_no_output";
		state.detect();
		return true;
	});
}

Dictionary ControllerHapticsBackend::get_capabilities() { return capabilities_dictionary(impl->snapshot()); }

bool ControllerHapticsBackend::set_output(double left_hz, double left_strength, double right_hz, double right_strength,
		double frequency_multiplier, double strength_multiplier) {
	const Request request{ left_hz, left_strength, right_hz, right_strength, frequency_multiplier, strength_multiplier };
	// Creating a bridge or issuing an unbound command never initializes or starts native hardware.
	if (!impl->runtime) {
		impl->state.status.error = "No connected device is bound.";
		return false;
	}
	return impl->runtime->call([this, request] { return impl->state.set_output(request); });
}

void ControllerHapticsBackend::set_phase_reference(double left, double right) {
	auto update = [this, left, right] {
		auto &state = impl->state;
		if (!std::isfinite(left) || !std::isfinite(right)) {
			state.status.error = "Phase references must be finite unwrapped radians.";
			return;
		}
		state.advance_phase(Clock::now());
		state.status.phase = { left, right };
		if (state.status.running && state.candidate == SINE_EFFECT) state.apply();
	};
	if (impl->runtime) impl->runtime->call(update); else update();
}

void ControllerHapticsBackend::stop() {
	if (impl->runtime) impl->runtime->call([this] { impl->state.stop(); }); else impl->state.stop();
}

void ControllerHapticsBackend::unbind_device() {
	if (impl->runtime) impl->runtime->call([this] { impl->state.close(); }); else impl->state.close();
}

Dictionary ControllerHapticsBackend::get_output_status() {
	const Status s = impl->snapshot();
	Dictionary result, requested, submitted;
	requested["left_frequency_hz"] = s.request.left_hz;
	requested["left_strength"] = s.request.left_strength;
	requested["right_frequency_hz"] = s.request.right_hz;
	requested["right_strength"] = s.request.right_strength;
	requested["frequency_multiplier"] = s.request.frequency_multiplier;
	requested["strength_multiplier"] = s.request.strength_multiplier;
	submitted["left_strength"] = s.submitted.left_strength;
	submitted["right_strength"] = s.submitted.right_strength;
	submitted["mono_strength"] = s.submitted.mono_strength;
	submitted["frequency_hz"] = s.submitted.frequency_hz;
	submitted["phase_rad"] = s.submitted.phase_rad;
	submitted["period_ms"] = s.submitted.period_ms;
	submitted["phase_side"] = String::utf8(s.submitted.phase_side.c_str());
	result["device_id"] = s.device_id;
	result["has_request"] = s.has_request;
	result["output_active"] = s.running;
	result["accepted"] = s.accepted;
	result["mode"] = String::utf8(s.mode.c_str());
	result["backend"] = String::utf8(s.backend.c_str());
	result["reason"] = String::utf8(s.reason.c_str());
	result["last_error"] = String::utf8(s.error.c_str());
	result["requested"] = requested;
	result["submitted"] = submitted;
	result["left_unwrapped_phase_rad"] = s.phase[0];
	result["right_unwrapped_phase_rad"] = s.phase[1];
	result["phase_applied"] = s.running && s.mode == "mono_periodic";
	result["lease_ms"] = int64_t(LEASE_MS);
	result["renew_interval_sec"] = 20.0;
	result["hardware_measurement"] = false;
	return result;
}
}
