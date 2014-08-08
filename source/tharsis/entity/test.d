//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// A basic unittest for Tharsis.
module tharsis.entity.test;

import std.array;
import std.stdio;
import std.string;

import tharsis.entity.lifecomponent;
import tharsis.entity.componenttypeinfo;
import tharsis.entity.componenttypemanager;
import tharsis.entity.entitypolicy;
import tharsis.entity.entityid;
import tharsis.entity.entitymanager;
import tharsis.entity.entityprototype;
import tharsis.entity.lifecomponent;
import tharsis.entity.prototypemanager;
import tharsis.entity.resourcemanager;
import tharsis.defaults.components;
import tharsis.defaults.processes;
import tharsis.defaults.resources;
import tharsis.defaults.yamlsource;


    //        XXX XXX NOW SEPARATE 'tharsis-core' PACKAGE AND 'tharsis-full'
    //        XXX THEN 2 GITHUB REPOS - THATSIS-CORE, THARSIS-FULL
    //        XXX AND UPDATE HOMEPAGES IN BOTH OF THEIR package.json FILES
    //        XXX THEN VIM TODOS AND RESET VIM
    //        XXX AND DDOX!
//XXX study Entreri ECS framework - may have good ideas
//XXX study events in EntityX entity framework- may be useful for us
//XXX move some TODOs to issues.
//    For example: a GUI entity editor (using e.g. dimgui)
//
// XXX CONSIDER PROPOSING AN 'Advanced FOSS' LIKE SUBJECT LIKE THE ONE FROM
//     ROCHESTER INSTITUTE OF TECHNOLOGY

//  XXX TEST RELEASE BUILD
//  XXX assumeWontThrow!!!
//   ALSO assumePure (google it, not sure if can be found)
    //XXX Need at least these doc files (and more):
    //      * process.rst (concept, process() signature and overloads, preProcess()/postProcess() etc.)
    //      * resource-descriptor.rst
    //      * component.rst
    //    DDoc should link th them where it makes sense.
    //    (with something better than AutoDDoc if possible)
    //    We should also use Dub to get DMD and Derelict (not sure if the second will work)
   // XXX a page like:
   // https://github.com/neovim/neovim/wiki/Code-overview
   // to help with basic orientation over the source
    //XXX THARSIS: USE GITTER

// XXX CAN USE https://github.com/d-gamedev-team/dbox
// XXX XXX XXX:
//      Non-shared resources can be mutable. In fact we might need that for DBox.
//      Resource managers for such resource should always be 'locked' to a single 
//      Process (e.g. passing process reference to get handle).
//      Better 'locking': enabled by EntityManager only when running the specified
//      Process (and only in that thread - it should check that somehow).
//      Probably a separate hierarchy from ResourceManager,
//      and probably less formal?
//      But think about ways to reuse most code.
//      Call it MutableResourceManager? 
//              SingleProcessResourceManager?
//              OwnedResourceManager?
//      May be also derived from AbstractResourceManager.
//      Actually it can probably share most of ResourceManager API, with the 
//      notable exception of resource().
//

//XXX long-term future (post-thesis):
//    Consider replacing our custom serialization with Cerealed
//    Consider having the user specify all components at compile-time
//    (e.g. by a tuple of strings of module name, or just one module with public imports)

// XXX THREADING SOURCE: http://ddili.org/ders/d.en/concurrency_shared.html
//     (CAN USE IN THESIS ONCE THAT BOOK IS OUT)

// XXX once done with these TODOs, start p    orting ICE to Tharsis.
//     
//     Create a "simpler" subset of Tharsis, and maybe try DBox.
//     (should be a separate git repo. Finally use git submodules?
//     try to find out if they can be automatically pulled)
//
//     Use it with stuff like dimgui, gl3n, that gl util lib (gfm?), etc
//                            (maybe speed for networking)
//XXX in YAML, strip the 'multi' prefix for multi component types.
//    Or turn it into a 'm' or 'mti' prefix
//XXX add an annotation for multi/component types to force the EntityManager to 
//    automatically provide a CopyProcess (which will still be overridable)
//    - call it @("persistent")

//XXX entity prototype with no components should be an error




/// A simple MultiComponent type for testing.
struct TestMultiComponent
{
    enum ComponentTypeID = userComponentTypeID!4;
    /// No more than 256 TestMultiComponents per entity.
    enum maxComponentsPerEntity = 256;

    /// Content of the component.
    bool value = true;
}

/// A Process type processing TestMultiComponent.
class TestMultiComponentProcess
{
public:
    alias TestMultiComponent FutureComponent;

    /// Params: life     = The LifeComponent, to test with a longer signature.
    ///         multi    = The past TestMultiComponent.
    ///         outMulti = The future TestMultiComponent.
    void process(ref const LifeComponent life, 
                 const TestMultiComponent[] multi,
                 ref TestMultiComponent[] outMulti)
    {
        outMulti = outMulti[0 .. multi.length];
        outMulti[] = multi[];
    }
}

struct TimeoutComponent
{
    enum ushort ComponentTypeID = userComponentTypeID!1;

    enum minPrealloc = 8192;

    int removeIn;

    int killEntityIn;
}

class TestRemoveComponentProcess
{
public:
    alias TimeoutComponent FutureComponent;

    void process(ref const TimeoutComponent timeout, 
                 ref TimeoutComponent* outTimeout)
    {
        if(timeout.removeIn == 0)
        {
            outTimeout = null;
            return;
        }

        *outTimeout = timeout;
        outTimeout.removeIn     = timeout.removeIn - 1;
        outTimeout.killEntityIn = timeout.killEntityIn - 1;
    }

    void process(ref const TimeoutComponent timeout, 
                 ref const PhysicsComponent physics,
                 ref TimeoutComponent* outTimeout)
    {
        if(timeout.removeIn == 0)
        {
            outTimeout = null;
            return;
        }

        *outTimeout = timeout;
        outTimeout.removeIn     = timeout.removeIn - 1;
        outTimeout.killEntityIn = timeout.killEntityIn - 1;
    }
}


struct PhysicsComponent
{
    enum ushort ComponentTypeID = userComponentTypeID!2;

    enum minPrealloc = 16384;

    enum minPreallocPerEntity = 1.0;

    @("relative", "someOtherAttrib") float x;
    @("relative") float y;
    @("relative") float z;
}

class TestLifeProcess
{
public:
    alias LifeComponent FutureComponent;

    void process(ref const TimeoutComponent timeout, 
                 ref const LifeComponent life,
                 out LifeComponent outLife)
    {
        outLife = life;
        if(timeout.killEntityIn == 0) 
        {
            writeln("KILLING ENTITY");
            outLife.alive = false; 
        }
    }

    void process(ref const LifeComponent life, out LifeComponent outLife)
    {
        outLife = life;
    }
}

class TestNoOutputProcess
{
public:
    void process(ref const LifeComponent life)
    {
        /*writeln("TestNoOutputProcess: ", life);*/
    }
}

void realMain()
{   
    writeln(q{
    ==========
    MAIN START
    ==========
    });

    auto compTypeMgr = new ComponentTypeManager!YAMLSource(YAMLSource.Loader());
    compTypeMgr.registerComponentTypes!TimeoutComponent();
    compTypeMgr.registerComponentTypes!PhysicsComponent();
    compTypeMgr.registerComponentTypes!TestMultiComponent();
    compTypeMgr.registerComponentTypes!SpawnerMultiComponent();
    compTypeMgr.registerComponentTypes!TimedSpawnConditionMultiComponent();
    compTypeMgr.lock();


    auto entityMgr      = new EntityManager!DefaultEntityPolicy(compTypeMgr);
    scope(exit) { entityMgr.destroy(); }

    auto protoMgr       = new PrototypeManager(compTypeMgr, entityMgr);
    auto inlineProtoMgr = new InlinePrototypeManager(compTypeMgr, entityMgr);

    auto lifeProc        = new TestLifeProcess();
    auto noOutProc       = new TestNoOutputProcess();
    auto physicsProc     = new CopyProcess!PhysicsComponent();
    physicsProc.printComponents = true;
    auto spawnerCopyProc = new CopyProcess!SpawnerMultiComponent();
    auto removeProc      = new TestRemoveComponentProcess();
    auto multiProc       = new TestMultiComponentProcess();
    //XXX implement time management and replace this "1.0 / 60" hack.
    //    A TimeManager class, with 'fixed time manager' and 
    //    'fast time manager' implementations. Passed to EntityManager
    //    in a setter; will also have some kind of default.
    //
    auto timedSpawnConditionProc =
        new TimedSpawnConditionProcess(delegate double(){return 1.0 / 60;});

    auto spawnerProc = new SpawnerProcess!DefaultEntityPolicy 
                               (&entityMgr.addEntity,
                                protoMgr,
                                inlineProtoMgr,
                                compTypeMgr);
    entityMgr.registerProcess(lifeProc);
    entityMgr.registerProcess(noOutProc);
    entityMgr.registerProcess(physicsProc);
    entityMgr.registerProcess(removeProc);
    entityMgr.registerProcess(multiProc);
    entityMgr.registerProcess(spawnerProc);
    entityMgr.registerProcess(spawnerCopyProc);
    entityMgr.registerProcess(timedSpawnConditionProc);
    entityMgr.registerResourceManager(protoMgr);
    entityMgr.registerResourceManager(inlineProtoMgr);


    int[][8] entityNumbers = [[1],
                              [],
                              [2, 3],
                              [1, 2, 3],
                              [],
                              [1],
                              [3, 3, 4],
                              [4, 5, 1]];
    ResourceHandle!EntityPrototypeResource[][8] entityHandles;
    EntityID[][8] entityIDs;
    foreach(frame; 0 .. 8) foreach(number; entityNumbers[frame])
    {
        auto descriptor = EntityPrototypeResource.
                          Descriptor("test_data/entity%s.yaml".format(number));
        writeln(descriptor.fileName);
        entityHandles[frame] ~= protoMgr.handle(descriptor);
        entityIDs[frame] ~= EntityID.init;

        protoMgr.requestLoad(entityHandles[frame].back);
    }


    foreach(frame; 0 .. 8)
    {
        writeln(q{
        --------
        FRAME %s
        --------
        }.format(frame));

        entityMgr.executeFrame();
        ResourceHandle!EntityPrototypeResource[] handles = 
            entityHandles[frame][];
        EntityID[] ids                           = entityIDs[frame][];
        foreach(i, ref handle; handles)
        {
            if(protoMgr.state(handle) == ResourceState.Loaded &&
               ids[i].isNull)
            {
                /*writefln("Going to add entity %s %s", frame, handle);*/
                immutable(EntityPrototype)* prototype = 
                    &(protoMgr.resource(handle).prototype);
                ids[i] = entityMgr.addEntity(*prototype);
            }
        }
    }
}

unittest
{
    try
    {
        realMain();
    }
    catch(Error e)
    {
        writeln("ERROR");
        writeln(e.msg);
        writeln(e);
    }
}
