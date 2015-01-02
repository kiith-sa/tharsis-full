//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module tharsis.defaults.yamlsource;


import std.exception: assumeWontThrow;
import std.string: format, strip, split;

import dyaml.loader;
import dyaml.node;
import dyaml.exception;


/** A Source to load entity components from based on YAML.
 *
 * Note: To allow sane component properties by default, `enum` values can be loaded
 *       directly from strings and 2D/3D/4D `gl3n <https://github.com/Dav1dde/gl3n>`_
 *       vectors can be loaded from 2/3/4-number sequences.
 *
 *       E.g.:
 *
 *       ```
 *       value: EnumValue
 *       ```
 *
 *       can be read as `Enum.EnumValue` if `Enum` is an `enum` type and we're
 *       YAMLSource.readTo!Enum is called.
 *
 *       As for vectors,
 *
 *       ```
 *       vector: [2.0, 1.0, 3.5]
 *       ```
 *
 *       can be read as `gl3n.linalg.vec3` or `gl3n.linalg.vec3d`.
 */
struct YAMLSource
{
private:
    /// The underlying YAML node.
    dyaml.node.Node yaml_;

    /// Errors logged during construction and use of this YAMLSource.
    string errorLog_;

    /// Should we log errors? (Disabled by default for performance).
    bool logErrors_ = false;

public:
    /// Handles loading of Sources.
    struct Loader
    {
    public:
        /** Load a Source.
         *
         * Params: name      = Name to identify the source by (e.g. a file name).
         *         logErrors = If true, any errors generated during the use of the Source
         *                     (such as loading errors, conversion errors, etc.) should be
         *                     logged, accessible through the errorLog() method of Source.
         *
         * There is no requirement to load from actual files; this may be implemented by
         * loading from some archive file or from memory.
         */
        YAMLSource loadSource(string name, bool logErrors = false)
            @trusted nothrow
        {
            try
            {
                return YAMLSource(dyaml.loader.Loader(name).load());
            }
            catch(YAMLException e)
            {
                auto result = YAMLSource(dyaml.node.Node(YAMLNull()));
                result.logErrors_ = logErrors;
                if(logErrors)
                {
                    result.errorLog_ = "Loader.loadSource: %s: %s\n"
                                       .format(e, e.msg).assumeWontThrow;
                }
                return result;
            }
            catch(Exception e)
            {
                assert(false, "Unexpected exception in Loader.loadSource");
            }
        }
    }

    /// If true, the Source is 'null' and doesn't store anything.
    ///
    /// A null source may be returned when loading a Source fails, e.g.
    /// from Loader.loadSource().
    bool isNull() @safe nothrow const { return yaml_.isNull(); }

    /// If logging is enabled, returns errors logged during construction and use
    /// of this Source. Otherwise returns a warning message.
    string errorLog() @safe pure nothrow const
    {
        return logErrors_ ? errorLog_ :
               "WARNING: Logging not enabled for this YAMLSource. Pass logErrors == true "
               "to YAMLSource.Loader.loadSource to enable logging\n";
    }

    /** Read a value of type T to target.
     *
     * Returns: `true` if the value was successfully read.
     *          `false` if the Source isn't convertible to specified type.
     */
    bool readTo(T)(out T target) @trusted nothrow
    {
        import std.exception: assumeWontThrow;

        void logError(string str)
        {
            if(logErrors_) { errorLog_ ~= "YAMLSource.readTo(): " ~ str; }
        }

        import std.conv: to, ConvException;
        import std.traits: EnumMembers, fullyQualifiedName;

        try
        {
            enum fullTName = fullyQualifiedName!T;
            import std.algorithm: map, startsWith;
            // TODO special handling for GFM vectors as well
            // Builtin handling for vector types as they're *very* common in games and
            // entity components.
            static if(fullTName.startsWith("gl3n.linalg.Vector!"))
            {
                enum vectorParams = fullTName["gl3n.linalg.Vector!".length + 1 .. $ - 1]
                                    .split(",")
                                    .map!(s => s.strip);
                mixin(q{
                alias Coord = %s;
                enum dims = %s;
                }.format(vectorParams[0], vectorParams[1]));

                // If it's an array, it may the special case vector format;
                // any exceptions there are actual errors.
                if(yaml_.length > 1)
                {
                    if(yaml_.length != dims)
                    {
                        logError("Unexpected number of vector dimensions; expected %s".format(dims));
                        return false;
                    }

                    foreach(dim; 0 .. dims)
                    {
                        target.vector[dim] = yaml_[dim].as!Coord;
                    }
                    return true;
                }

                // Fallback to the default handling
            }
            // Builtin special handling for enums
            else static if(is(T == enum))
            {
                try
                {
                    const str = yaml_.as!string;
                    target = str.to!T;
                    return true;
                }
                catch(ConvException e)
                {
                    logError("Invalid value of an enum: %s\nValid values are: %s"
                            .format(e.msg, EnumMembers!T).assumeWontThrow);
                    return false;
                }
                // Ignore; maybe it's really an enum, not a string
                catch(NodeException e) { }
            }

            target = yaml_.as!T;
        }
        catch(NodeException e)
        {
            logError("%s: %s\n".format(e, e.msg).assumeWontThrow);
            return false;
        }
        catch(Exception e)
        {
            assert(false, "Unexpected exception in YAMLSource.readTo()");
        }
        return true;
    }

    /// Assign one YAMLSource to another.
    void opAssign(Source)(auto ref Source rhs) @safe nothrow
        if(is(Source == YAMLSource))
    {
        yaml_ = rhs.yaml_;
    }

    /** Foreach over all members of a sequence Source or over all keys of a mapping Source.
     *
     * Note:
     *
     * Body of the foreach loop must be nothrow. Use std.exception.assumeWontThrow if
     * necessary.
     */
    int opApply(int delegate(ref YAMLSource) nothrow dg) @trusted nothrow
    {
        int result = 0;

        if(yaml_.isNull) { return result; }

        int implementation()
        {
            if(isSequence) foreach(ref dyaml.node.Node item; yaml_)
            {
                auto source = YAMLSource(item);
                result = dg(source);
                if(result) { break; }
            }
            else if(isMapping) foreach(ref dyaml.node.Node key, ref dyaml.node.Node value; yaml_)
            {
                auto source = YAMLSource(key);
                result = dg(source);
                if(result) { break; }
            }
            else assert(false, "opApply() called on a scalar YAMLSource");
            return result;
        }

        return implementation.assumeWontThrow();
    }

    /** Get a nested Source from a mapping Source.
     *
     * (Get a value from a Source that maps strings to Sources)
     *
     * Can only be called on if the Source is a mapping (see isMapping()).
     *
     * Params: key    = Key identifying the nested source..
     *         target = Target to read the nested source to.
     *
     * Returns: true on success, false if there is no such key in the mapping.
     */
    bool getMappingValue(string key, out YAMLSource target)
        @trusted nothrow
    {
        // Null works as a scalar, sequence and mapping at the same time; this way we
        // can have e.g. empty mappings without explicit "{}".
        if(yaml_.isNull) { return false; }
        if(!yaml_.isMapping)
        {
            assert(false, "Called getMappingValue() on a non-mapping YAMLSource");
        }

        // Hack to allow nothrow to work.
        bool implementation(string key, ref YAMLSource target)
        {
            if(!yaml_.containsKey(key)) { return false; }

            try
            {
                alias ref dyaml.node.Node delegate(string) const constIdx;
                target = YAMLSource((cast(constIdx)&yaml_.opIndex!string)(key));
            }
            catch(NodeException e)
            {
                assert(false, e.msg);
            }
            return true;
        }

        alias bool delegate(string, ref YAMLSource) nothrow nothrowFunc;
        return (cast(nothrowFunc)&implementation)(key, target);
    }

    /// Is this a scalar source? A scalar is any source that is not a sequence or a mapping.
    bool isScalar() @safe nothrow const { return yaml_.isScalar(); }

    /// Is this a sequence source? A sequence acts as an array of values of various types.
    bool isSequence() @safe nothrow const { return yaml_.isSequence() || yaml_.isNull; }

    /// Is this a mapping source? A mapping acts as an associative array of various types.
    bool isMapping() @safe nothrow const { return yaml_.isMapping() || yaml_.isNull; }
}
