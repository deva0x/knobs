import KnobsCore
import Testing

@Suite struct ManifestSchemaTests {
    @Test func supportsVersionOneOfTheManifestFormat() {
        #expect(ManifestSchema.supportedVersion == 1)
    }
}
