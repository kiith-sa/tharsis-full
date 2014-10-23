//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module tharsis.entity.testentitymanager;


import tharsis.entity.componenttypeinfo;
import tharsis.entity.componenttypemanager;
import tharsis.entity.entitymanager;
import tharsis.entity.entitypolicy;


private struct TestSource
{
public:
    struct Loader
    {
        TestSource loadSource(string name, bool logErrors = false) @safe nothrow
        {
            assert(false);
        }
    }

    bool isNull() @safe nothrow const
    {
        assert(false);
    }

    string errorLog() @safe pure nothrow const
    {
        assert(false);
    }

    bool readTo(T)(out T target) @safe nothrow
    {
        assert(false);
    }

    bool getSequenceValue(size_t index, out TestSource target) @safe nothrow
    {
        assert(false);
    }

    bool getMappingValue(string key, out TestSource target) @safe nothrow
    {
        assert(false);
    }

    bool isScalar() @safe nothrow const
    {
        assert(false);
    }

    bool isSequence() @safe nothrow const
    {
        assert(false);
    }

    bool isMapping() @safe nothrow const
    {
        assert(false);
    }
}

unittest
{
    /// Not a 'real' Source, just for testing.
    struct TimeoutComponent
    {
        enum ushort ComponentTypeID = userComponentTypeID!1;

        enum minPrealloc = 8192;

        int killEntityIn;
    }

    struct PhysicsComponent
    {
        enum ushort ComponentTypeID = userComponentTypeID!2;

        enum minPrealloc = 16384;

        enum minPreallocPerEntity = 1.0;

        float x;
        float y;
        float z;
    }


    import tharsis.defaults.copyprocess;
    auto compTypeMgr = new ComponentTypeManager!TestSource(TestSource.Loader());
    compTypeMgr.registerComponentTypes!TimeoutComponent();
    compTypeMgr.registerComponentTypes!PhysicsComponent();
    compTypeMgr.lock();
    auto entityManager = new EntityManager!DefaultEntityPolicy(compTypeMgr);
    scope(exit) { entityManager.destroy(); }
    entityManager.startThreads();
    auto process = new CopyProcess!TimeoutComponent();
    entityManager.registerProcess(process);
}
