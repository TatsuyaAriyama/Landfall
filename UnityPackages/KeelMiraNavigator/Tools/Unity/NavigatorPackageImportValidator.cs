using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

public static class NavigatorPackageImportValidator
{
    private const string Root = "Assets/KeelMira/Navigator";
    private const string PrefabPath = Root + "/Prefabs/KeelMiraNavigator.prefab";
    private const string ScenePath = Root + "/Samples/NavigatorShowcase.unity";

    public static void ValidateAndBuild()
    {
        GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>(PrefabPath);
        if (prefab == null)
            throw new InvalidOperationException("Imported navigator prefab is missing");

        bool hasController = false;
        foreach (Component component in prefab.GetComponents<Component>())
        {
            if (component != null && component.GetType().FullName == "KeelMira.Navigator.KeelMiraNavigatorController")
                hasController = true;
        }
        if (!hasController)
            throw new InvalidOperationException("Imported navigator controller is missing");
        if (prefab.GetComponent<CapsuleCollider>() == null)
            throw new InvalidOperationException("Imported navigator collider is missing");

        string[] required =
        {
            "Root", "Spine", "Head", "Arm.L", "Arm.R", "Leg.L", "Leg.R",
            "GripSocket.L", "GripSocket.R", "BackSocket", "HeadSocket"
        };
        foreach (string name in required)
        {
            if (Find(prefab.transform, name) == null)
                throw new InvalidOperationException("Imported rig node is missing: " + name);
        }

        foreach (Renderer renderer in prefab.GetComponentsInChildren<Renderer>(true))
        {
            foreach (Material material in renderer.sharedMaterials)
            {
                if (material == null || material.shader == null || material.shader.name == "Hidden/InternalErrorShader")
                    throw new InvalidOperationException("Navigator contains an invalid material");
            }
        }

        string buildPath = Environment.GetEnvironmentVariable("NAVIGATOR_TEST_BUILD");
        if (string.IsNullOrWhiteSpace(buildPath))
            throw new InvalidOperationException("NAVIGATOR_TEST_BUILD is required");
        Directory.CreateDirectory(Path.GetDirectoryName(buildPath));

        BuildPlayerOptions options = new BuildPlayerOptions
        {
            scenes = new[] { ScenePath },
            locationPathName = buildPath,
            target = BuildTarget.StandaloneOSX,
            options = BuildOptions.Development
        };
        BuildReport report = BuildPipeline.BuildPlayer(options);
        if (report.summary.result != BuildResult.Succeeded)
            throw new InvalidOperationException("Navigator test player build failed: " + report.summary.result);

        Debug.Log("NAVIGATOR_CLEAN_IMPORT_VALID=true");
        Debug.Log("NAVIGATOR_TEST_BUILD_BYTES=" + report.summary.totalSize);
    }

    private static Transform Find(Transform root, string name)
    {
        if (root.name == name)
            return root;
        foreach (Transform child in root)
        {
            Transform match = Find(child, name);
            if (match != null)
                return match;
        }
        return null;
    }
}
