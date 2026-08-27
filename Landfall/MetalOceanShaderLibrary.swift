import Metal

/// Preflights the native ocean program before SceneKit switches away from its
/// shader-modifier fallback. Keeping this check separate makes each migration
/// step reversible and prevents a missing metallib symbol from blanking the sea.
enum MetalOceanShaderLibrary {
    static let vertexFunctionName = "landfallOceanVertex"
    private static let compatibleFragment = "landfallOceanFragmentCompatible"
    private static let enhancedFragment = "landfallOceanFragmentEnhanced"
    private static let ultraFragment = "landfallOceanFragmentUltra"

    static func fragmentFunctionName(for tier: MetalRenderingProfile.Tier) -> String {
        switch tier {
        case .compatible: compatibleFragment
        case .enhanced: enhancedFragment
        case .ultra: ultraFragment
        }
    }

    static func isAvailable(on device: MTLDevice) -> Bool {
        makeLibrary(on: device) != nil
    }

    static func makeLibrary(on device: MTLDevice) -> MTLLibrary? {
        guard let library = device.makeDefaultLibrary(),
              library.makeFunction(name: vertexFunctionName) != nil,
              library.makeFunction(name: compatibleFragment) != nil,
              library.makeFunction(name: enhancedFragment) != nil,
              library.makeFunction(name: ultraFragment) != nil else {
            return nil
        }
        return library
    }
}
