import Metal

/// Preflights the native ocean program before SceneKit switches away from its
/// shader-modifier fallback. Keeping this check separate makes each migration
/// step reversible and prevents a missing metallib symbol from blanking the sea.
enum MetalOceanShaderLibrary {
    static let vertexFunctionName = "landfallOceanVertex"
    static let fragmentFunctionName = "landfallOceanFragment"

    static func isAvailable(on device: MTLDevice) -> Bool {
        guard let library = device.makeDefaultLibrary() else { return false }
        return library.makeFunction(name: vertexFunctionName) != nil
            && library.makeFunction(name: fragmentFunctionName) != nil
    }
}
