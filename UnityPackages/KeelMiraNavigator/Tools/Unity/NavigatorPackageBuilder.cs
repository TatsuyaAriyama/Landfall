using System;
using System.IO;
using KeelMira.Navigator;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

public static class NavigatorPackageBuilder
{
    private const string Root = "Assets/KeelMira/Navigator";
    private const string ModelPath = Root + "/Models/Navigator.fbx";
    private const string PrefabPath = Root + "/Prefabs/KeelMiraNavigator.prefab";
    private const string ScenePath = Root + "/Samples/NavigatorShowcase.unity";

    public static void Build()
    {
        ConfigureModelImporter();
        AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);

        GameObject source = AssetDatabase.LoadAssetAtPath<GameObject>(ModelPath);
        if (source == null)
            throw new InvalidOperationException("Navigator FBX could not be imported: " + ModelPath);

        Directory.CreateDirectory(Path.GetDirectoryName(PrefabPath));
        GameObject instance = PrefabUtility.InstantiatePrefab(source) as GameObject;
        if (instance == null)
            throw new InvalidOperationException("Navigator FBX could not be instantiated");

        instance.name = "KeelMiraNavigator";
        instance.AddComponent<KeelMiraNavigatorController>();
        CapsuleCollider collider = instance.AddComponent<CapsuleCollider>();
        collider.center = new Vector3(0f, 0.65f, 0f);
        collider.height = 1.3f;
        collider.radius = 0.27f;
        collider.direction = 1;
        PrefabUtility.SaveAsPrefabAsset(instance, PrefabPath);
        UnityEngine.Object.DestroyImmediate(instance);

        BuildShowcaseScene();
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();

        string output = Environment.GetEnvironmentVariable("NAVIGATOR_PACKAGE_OUTPUT");
        if (string.IsNullOrWhiteSpace(output))
            throw new InvalidOperationException("NAVIGATOR_PACKAGE_OUTPUT is required");

        Directory.CreateDirectory(Path.GetDirectoryName(output));
        AssetDatabase.ExportPackage(Root, output, ExportPackageOptions.Recurse);
        Debug.Log("NAVIGATOR_PACKAGE_BUILT=" + output);
    }

    private static void ConfigureModelImporter()
    {
        AssetImporter importerAsset = AssetImporter.GetAtPath(ModelPath);
        if (!(importerAsset is ModelImporter importer))
            throw new InvalidOperationException("ModelImporter was not available for " + ModelPath);

        importer.globalScale = 1f;
        importer.useFileScale = true;
        importer.importCameras = false;
        importer.importLights = false;
        importer.importBlendShapes = false;
        importer.importVisibility = false;
        importer.importAnimation = false;
        importer.animationType = ModelImporterAnimationType.Generic;
        importer.materialImportMode = ModelImporterMaterialImportMode.ImportStandard;
        importer.materialLocation = ModelImporterMaterialLocation.InPrefab;
        importer.SaveAndReimport();
    }

    private static void BuildShowcaseScene()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(ScenePath));
        Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

        GameObject navigatorPrefab = AssetDatabase.LoadAssetAtPath<GameObject>(PrefabPath);
        GameObject navigator = PrefabUtility.InstantiatePrefab(navigatorPrefab) as GameObject;
        navigator.transform.position = Vector3.zero;

        GameObject floor = GameObject.CreatePrimitive(PrimitiveType.Plane);
        floor.name = "Ground_1m_Reference";
        floor.transform.localScale = Vector3.one * 0.4f;

        GameObject key = new GameObject("Key Light", typeof(Light));
        key.transform.rotation = Quaternion.Euler(46f, -35f, 0f);
        Light keyLight = key.GetComponent<Light>();
        keyLight.type = LightType.Directional;
        keyLight.intensity = 1.4f;

        GameObject fill = new GameObject("Fill Light", typeof(Light));
        fill.transform.position = new Vector3(-1.5f, 1.6f, -1.5f);
        Light fillLight = fill.GetComponent<Light>();
        fillLight.type = LightType.Point;
        fillLight.range = 6f;
        fillLight.intensity = 3f;
        fillLight.color = new Color(0.52f, 0.72f, 0.82f);

        GameObject cameraObject = new GameObject("Main Camera", typeof(Camera), typeof(AudioListener));
        cameraObject.tag = "MainCamera";
        cameraObject.transform.position = new Vector3(0f, 0.9f, -2.7f);
        cameraObject.transform.LookAt(new Vector3(0f, 0.68f, 0f));
        cameraObject.GetComponent<Camera>().fieldOfView = 35f;

        EditorSceneManager.SaveScene(scene, ScenePath);
    }

    public static void Validate()
    {
        GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>(PrefabPath);
        if (prefab == null)
            throw new InvalidOperationException("Prefab is missing");
        if (prefab.GetComponent<KeelMiraNavigatorController>() == null)
            throw new InvalidOperationException("Navigator controller is missing");
        if (prefab.GetComponent<CapsuleCollider>() == null)
            throw new InvalidOperationException("Navigator collider is missing");

        string[] required = { "Root", "Spine", "Head", "Arm.L", "Arm.R", "Leg.L", "Leg.R" };
        foreach (string name in required)
        {
            if (Find(prefab.transform, name) == null)
                throw new InvalidOperationException("Required rig node is missing: " + name);
        }
        Debug.Log("NAVIGATOR_PACKAGE_VALID=true");
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
