//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Utility functions for Tharsis diagnostics.
module tharsis.defaults.diagnostics;


import dyaml.all;
alias YAMLNode = Node;

import tharsis.entity.diagnostics;
import tharsis.entity.entitymanager;
import tharsis.util.units;


/// Convert EntityManager diagnostics to YAML.
YAMLNode toYAML(Policy)(ref const EntityManagerDiagnostics!Policy diagnostics)
    @safe nothrow
{
    try with(diagnostics)
    {
        import dyaml.hacks;

        YAMLNode[] yamlTypes;
        foreach(ushort typeID, ref type; componentTypes) if(!type.isNull)
        {
            auto yamlType = YAMLNode(["name"], [type.name]);
            yamlType["pastComponentCount"]      = type.pastComponentCount;
            yamlType["pastComponentsPerEntity"] = pastComponentsPerEntity(typeID);
            yamlType["pastMemoryAllocated"]     = type.pastMemoryAllocated;
            yamlType["pastMemoryUsed"]          = type.pastMemoryUsed;
            yamlType["pastMemoryAllocatedMiB"]  = MBytes(type.pastMemoryAllocated).size;
            yamlType["pastMemoryUsedMiB"]       = MBytes(type.pastMemoryUsed).size;
            yamlType.collectionStyleHack = CollectionStyle.Block;
            yamlTypes ~= yamlType;
        }

        auto yaml = YAMLNode(["componentTypes"], [YAMLNode(yamlTypes)]);

        YAMLNode[] yamlProcesses;
        foreach(ref process; processes)
        {
            auto yamlProcess = YAMLNode(["name"], [process.name]);
            yamlProcess["processCalls"]       = process.processCalls;
            yamlProcess["componentTypesRead"] = process.componentTypesRead;
            yamlProcess["duration-hnsecs"]    = process.duration;
            yamlProcess.collectionStyleHack = CollectionStyle.Block;
            yamlProcesses ~= yamlProcess;
        }
        yaml["processes"] = YAMLNode(yamlProcesses);

        YAMLNode[] yamlThreads;
        foreach(ref thread; threads[0 .. threadCount])
        {
            yamlThreads ~= YAMLNode(["processesDuration"], [thread.processesDuration]);
        }
        yaml["threads"] = YAMLNode(yamlThreads);

        auto timeEstimator = YAMLNode(["totalProcessError"], 
                                      [scheduler.timeEstimator.totalProcessError]);
        with(scheduler.timeEstimator)
        {
            timeEstimator["totalProcessUnderestimate"]        = totalProcessUnderestimate;
            timeEstimator["maxProcessUnderestimate"]          = maxProcessUnderestimate;
            timeEstimator["averageProcessErrorRatio"]         = averageProcessErrorRatio;
            timeEstimator["averageProcessUnderestimateRatio"] = averageProcessUnderestimateRatio;
            timeEstimator["maxProcessUnderestimateRatio"]     = maxProcessUnderestimateRatio;
            timeEstimator.collectionStyleHack = CollectionStyle.Block;
        }
        auto yamlScheduler = YAMLNode(["schedulingAlgorithm"], [scheduler.schedulingAlgorithm]);
        yamlScheduler["approximate"]        = cast(bool)scheduler.approximate;
        yamlScheduler["estimatedFrameTime"] = scheduler.estimatedFrameTime;
        yamlScheduler["timeEstimator"]      = timeEstimator;
        yaml["scheduler"] = yamlScheduler;

        yaml["pastEntityCount"]              = pastEntityCount;
        yaml["processCount"]                 = processCount;
        yaml["threadCount"]                  = threadCount;
        yaml["pastComponentsTotal"]          = pastComponentsTotal;
        yaml["pastComponentsPerEntityTotal"] = pastComponentsPerEntityTotal;
        yaml["processCallsTotal"]            = processCallsTotal;
        yaml["processCallsPerEntity"]        = processCallsPerEntity;
        yaml["processDurationTotal"]         = processDurationTotal;
        yaml["processDurationAverage"]       = processDurationAverage;
        yaml["pastMemoryAllocatedTotal"]     = pastMemoryAllocatedTotal;
        yaml["pastMemoryUsedTotal"]          = pastMemoryUsedTotal;
        yaml["pastMemoryAllocatedTotalMiB"]  = MBytes(pastMemoryAllocatedTotal).size;
        yaml["pastMemoryUsedTotalMiB"]       = MBytes(pastMemoryUsedTotal).size;
        yaml["pastMemoryUsedPerEntity"]      = pastMemoryUsedPerEntity;
        yaml["componentTypesReadPerProcess"] = componentTypesReadPerProcess;

        return yaml;
    }
    catch(Exception e)
    {
        assert(false, "Unexpected exception in EntityManager diagnostics to YAML conversion");
    }
}
unittest
{
    const diagnostics = DefaultEntityManager.Diagnostics.init;
    auto yaml = toYAML(diagnostics);
}

