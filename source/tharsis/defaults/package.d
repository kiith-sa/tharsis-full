//          Copyright Ferdinand Majerech 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

// TODO update the last paragraph with (unless you build your prototypes completely in
// code, without loading anything) when we get EntityPrototype construction in code
// to work.
/** Non-core Tharsis features.
 *
 * This package provides utility code needed to comfortably work with Tharsis that cannot
 * be in the core package e.g. because of requiring dependencies, such as:
 *
 * * A Source implementation using YAML: YAMLSource
 *
 *   Some kind of a Source is needed to load EntityPrototypes. The default implementation
 *   uses YAML, based on the `D:YAML <https://github.com/kiith-sa/D-YAML>`_ library.
 *
 *   Of course your project may want to use a different format, but YAMLSource is useful
 *   if you want to get started without having to write code to load entity prototypes
 *   from.
 *
 * * A basic Component and (*customizable*) Process for spawning entities
 *   (e.g. tharsis.defaults.components, tharsis.defaults.processes)
 * * Utilities to simplify writing Processes (e.g. tharsis.defaults.copyprocess)
 */
module tharsis.defaults;


public:
    import tharsis.defaults.components;
    import tharsis.defaults.copyprocess;
    import tharsis.defaults.descriptors;
    import tharsis.defaults.diagnostics;
    import tharsis.defaults.processes;
    import tharsis.defaults.resources;
    import tharsis.defaults.yamlsource;
