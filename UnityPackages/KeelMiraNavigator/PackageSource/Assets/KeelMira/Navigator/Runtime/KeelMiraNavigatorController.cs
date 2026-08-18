using System;
using System.Collections.Generic;
using UnityEngine;

namespace KeelMira.Navigator
{
    public enum NavigatorPose
    {
        Idle,
        Walk,
        Lookout,
        Wave,
        Point,
        Rest
    }

    [DisallowMultipleComponent]
    public sealed class KeelMiraNavigatorController : MonoBehaviour
    {
        [SerializeField] private NavigatorPose pose = NavigatorPose.Idle;
        [SerializeField, Min(0.1f)] private float animationSpeed = 1f;
        [SerializeField, Range(0f, 30f)] private float blendSpeed = 12f;
        [SerializeField] private bool animate = true;

        private readonly Dictionary<string, Transform> parts = new Dictionary<string, Transform>();
        private readonly Dictionary<Transform, Quaternion> bindRotations = new Dictionary<Transform, Quaternion>();
        private readonly Dictionary<Transform, Vector3> bindPositions = new Dictionary<Transform, Vector3>();
        private readonly Dictionary<Transform, Vector3> bindScales = new Dictionary<Transform, Vector3>();
        private float clock;

        public NavigatorPose Pose => pose;

        public void SetPose(NavigatorPose nextPose)
        {
            pose = nextPose;
        }

        public void SetMoving(bool moving)
        {
            pose = moving ? NavigatorPose.Walk : NavigatorPose.Idle;
        }

        private void Awake()
        {
            CacheHierarchy();
        }

        private void OnEnable()
        {
            if (parts.Count == 0)
                CacheHierarchy();
        }

        private void CacheHierarchy()
        {
            parts.Clear();
            bindRotations.Clear();
            bindPositions.Clear();
            bindScales.Clear();

            foreach (Transform child in GetComponentsInChildren<Transform>(true))
            {
                if (!parts.ContainsKey(child.name))
                    parts.Add(child.name, child);

                bindRotations[child] = child.localRotation;
                bindPositions[child] = child.localPosition;
                bindScales[child] = child.localScale;
            }
        }

        private void Update()
        {
            if (!animate || parts.Count == 0)
                return;

            clock += Time.deltaTime * animationSpeed;
            ApplyPose(Time.deltaTime);
        }

        private void ApplyPose(float deltaTime)
        {
            float blend = blendSpeed <= 0f ? 1f : 1f - Mathf.Exp(-blendSpeed * deltaTime);
            float walk = pose == NavigatorPose.Walk ? Mathf.Sin(clock * 8f) : 0f;
            float breath = Mathf.Sin(clock * 1.7f);
            float scan = Mathf.Sin(clock * 0.65f);

            Vector3 coreEuler = Vector3.zero;
            Vector3 headEuler = new Vector3(0f, scan * 4f, 0f);
            Vector3 leftArmEuler = new Vector3(walk * -28f, 0f, -8f);
            Vector3 rightArmEuler = new Vector3(walk * 28f, 0f, 8f);
            Vector3 leftLegEuler = new Vector3(walk * 23f, 0f, 0f);
            Vector3 rightLegEuler = new Vector3(walk * -23f, 0f, 0f);

            switch (pose)
            {
                case NavigatorPose.Lookout:
                    leftArmEuler = new Vector3(-72f, 0f, -12f);
                    headEuler = new Vector3(-4f, scan * 18f, 0f);
                    coreEuler = new Vector3(5f, 0f, 0f);
                    break;
                case NavigatorPose.Wave:
                    rightArmEuler = new Vector3(-118f, 0f, 18f + Mathf.Sin(clock * 7f) * 18f);
                    break;
                case NavigatorPose.Point:
                    leftArmEuler = new Vector3(-86f, 0f, -6f);
                    coreEuler = new Vector3(7f, 0f, 0f);
                    headEuler = new Vector3(-3f, -4f, 0f);
                    break;
                case NavigatorPose.Rest:
                    leftArmEuler = new Vector3(34f, 0f, -17f);
                    rightArmEuler = new Vector3(34f, 0f, 17f);
                    coreEuler = new Vector3(-7f, 0f, 0f);
                    headEuler = new Vector3(12f, scan * 3f, 0f);
                    break;
            }

            RotatePart(coreEuler, blend, "core", "Spine");
            RotatePart(headEuler, blend, "head", "Head");
            RotatePart(leftArmEuler, blend, "armL", "Arm.L");
            RotatePart(rightArmEuler, blend, "armR", "Arm.R");
            RotatePart(leftLegEuler, blend, "legL", "Leg.L");
            RotatePart(rightLegEuler, blend, "legR", "Leg.R");

            if (parts.ContainsKey("cape"))
                RotatePart(new Vector3(-3f + breath * 1.5f, 0f, scan * 1.2f), blend, "cape");
            if (parts.ContainsKey("scarfTail"))
                RotatePart(new Vector3(-4f + breath * 3f, scan * 1.5f, 0f), blend, "scarfTail");

            Transform contact = FindPart("contact", "Root");
            if (contact != null)
            {
                Vector3 target = bindPositions[contact];
                if (pose == NavigatorPose.Walk)
                    target.y += Mathf.Abs(walk) * 0.025f;
                contact.localPosition = Vector3.Lerp(contact.localPosition, target, blend);
            }

            Transform core = FindPart("core", "Spine");
            if (core != null)
            {
                Vector3 scale = bindScales[core] * (1f + breath * 0.006f);
                core.localScale = Vector3.Lerp(core.localScale, scale, blend);
            }
        }

        private Transform FindPart(params string[] candidates)
        {
            foreach (string candidate in candidates)
            {
                if (parts.TryGetValue(candidate, out Transform part))
                    return part;
            }
            return null;
        }

        private void RotatePart(Vector3 relativeEuler, float blend, params string[] candidates)
        {
            Transform part = FindPart(candidates);
            if (part == null)
                return;

            Quaternion target = bindRotations[part] * Quaternion.Euler(relativeEuler);
            part.localRotation = Quaternion.Slerp(part.localRotation, target, blend);
        }

        private void OnValidate()
        {
            animationSpeed = Mathf.Max(0.1f, animationSpeed);
            blendSpeed = Mathf.Max(0f, blendSpeed);
        }
    }
}
