#include "controller_haptics_backend.h"
#include <godot_cpp/godot.hpp>

using namespace godot;

static void initialize_haptics(ModuleInitializationLevel level) {
	if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		ClassDB::register_class<ControllerHapticsBackend>();
	}
}

// Module loading registers the class only; it does not initialize SDL or probe/play devices.
extern "C" GDExtensionBool GDE_EXPORT wnm_haptics_init(
		GDExtensionInterfaceGetProcAddress get_proc_address,
		GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *initialization) {
	GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
	init.register_initializer(initialize_haptics);
	init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init.init();
}
