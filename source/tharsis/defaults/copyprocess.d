//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Utilities to easily copy past components that don't need to be added/removed to future.
module tharsis.defaults.copyprocess;

import tharsis.entity.componenttypeinfo;


/// Default PreserveComponents action. Does nothing.
void preserveComponentsActionNull(Component)(ref Component c) nothrow { }


/** A hack to make preserveComponents() easy to use until
 * [DLang issue #10556](https://issues.dlang.org/show_bug.cgi?id=10556) is fixed.
 *
 * See_Also: preserveComponents
 */
string preserveComponentsMixin(string action = null)()
{
    import std.string;
    return
    q{
        mixin preserveComponents%s _PRESERVE_COMPONENTS_;
        alias process = _PRESERVE_COMPONENTS_.process;
    }.format(action is null ? "" : "!" ~ action);
}

/** Generates a `process()` method that copies past component/s into future state, *preserving* them.
 *
 * Should me mixed in to Process classes; refers to the `FutureComponent` type of the 
 * Process to determine what component type to preserve. The generated `process()` method
 * will have the signature:
 *
 *     void process(ref const FutureComponent past, ref FutureComponent future)
 *
 * if `isMultiComponent!FutureComponent == false` or:
 *
 *     void process(immutable FutureComponent[] past, ref FutureComponent[] future)
 *
 * if `isMultiComponent!FutureComponent == true`.
 *
 * Note:
 *
 * Currently this should be used through the preserveComponentsMixin() function, e.g:
 *
 *     mixin(preserveComponentMixin);
 *
 * or:
 *
 *     mixin(preserveComponentMixin!"action");
 *
 * where `"action" ` is the name of the action function to use. This is needed at the 
 * moment but may become unnecessary once
 * [DLang issue #10556](https://issues.dlang.org/show_bug.cgi?id=10556) is resolved.
 *
 * Params:
 *
 * action = Function to call on each copied component. The default is a function that
 *          does nothing. This could be used to somehow modify the preserved component,
 *          or to read it and use the read information somehow in the Process.
 *
 *          Must have the following signature:
 *
 *              void action(ref FutureComponent component) nothrow;
 */
mixin template preserveComponents(alias action = preserveComponentsActionNull)
{
    import tharsis.entity.componenttypeinfo;

    static if(isMultiComponent!FutureComponent)
    {
        /// Preserve weapons in entities with no commands.
        void process(immutable FutureComponent[] past, ref FutureComponent[] future) nothrow
        {
            future = future[0 .. past.length];
            future[] = past[];

            // Request to load any weapons that are not loaded yet.
            foreach(ref component; future)
            {
                action(component);
            }
        }
    }
    else
    {
        void process(ref const FutureComponent past, out FutureComponent future) nothrow
        {
            future = past;
            action(future);
        }
    }
}


/** A dummy process template that preserves components of a component type into future.
 *
 * All this process does is that it copies the component of specified type into future
 * state, ensuring the component does not disappear.
 */
class CopyProcess(ComponentType)
{
    mixin validateComponent!ComponentType;

    /// If set to true, every processed component will be printed to stdout.
    bool printComponents_;

public:
    /// FutureComponent of this process is the copied component type.
    alias ComponentType FutureComponent;

    /// Copy past components into the future.
    mixin(preserveComponentsMixin!"action");

    /** If set to true, every processed component will be printed to stdout.
     *
     * Useful for debugging.
     */
    @property void printComponents(bool rhs) @safe pure nothrow 
    {
        printComponents_ = rhs;
    }

    /// Is printing of processed components to stdout enabled?
    @property bool printComponents() @safe const pure nothrow 
    {
        return printComponents_;
    }

private:
    /// Action executed on each copied component.
    void action(ref ComponentType component) nothrow
    {
        import std.stdio;
        import std.exception: assumeWontThrow;
        if(printComponents_) { writeln(component).assumeWontThrow; }
    }
}
