#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <memory>

namespace godot {

// Only this bridge touches native devices. No Gameplay or InputEventBuffer references.
class ControllerHapticsBackend : public RefCounted {
	GDCLASS(ControllerHapticsBackend, RefCounted)
	struct Impl;
	std::unique_ptr<Impl> impl;

protected:
	static void _bind_methods();

public:
	ControllerHapticsBackend();
	~ControllerHapticsBackend();
	// Enumeration initializes our private SDL runtime but never starts an effect.
	TypedArray<Dictionary> list_devices();
	// Stop the old binding, open this module's connection ID and query support without playback.
	bool bind_device(int64_t device_id);
	// Report usable capabilities separately from raw driver flags and runtime rejections.
	Dictionary get_capabilities();
	// Replaces the persistent target; invalid arguments leave the previous target intact.
	bool set_output(double left_hz, double left_strength, double right_hz, double right_strength,
			double frequency_multiplier, double strength_multiplier);
	// Set continuous input phases; never starts a stopped output or reads Gameplay state.
	void set_phase_reference(double left_phase_rad, double right_phase_rad);
	// Stops hardware and forgets the target/phases, retaining the device binding.
	void stop();
	// Stops and releases the device. No automatic reconnection or replay of old commands.
	void unbind_device();
	// Software request/submission snapshot, not a hardware measurement.
	Dictionary get_output_status();
};

}
