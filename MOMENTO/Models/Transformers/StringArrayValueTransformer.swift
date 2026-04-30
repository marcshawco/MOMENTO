import Foundation

@objc(StringArrayValueTransformer)
final class StringArrayValueTransformer: ValueTransformer {

    static let name = NSValueTransformerName(String(describing: StringArrayValueTransformer.self))

    override class func transformedValueClass() -> AnyClass {
        NSData.self
    }

    override class func allowsReverseTransformation() -> Bool {
        true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let value else {
            return nil
        }

        let tags: [String]
        if let typedTags = value as? [String] {
            tags = typedTags
        } else if let bridged = value as? NSArray {
            tags = bridged.compactMap { $0 as? String }
        } else {
            return nil
        }

        return try? JSONEncoder().encode(tags)
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let value else {
            return []
        }

        guard let data = value as? Data else {
            return []
        }

        guard let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return decoded
    }

    static func register() {
        ValueTransformer.setValueTransformer(StringArrayValueTransformer(), forName: name)
    }
}
