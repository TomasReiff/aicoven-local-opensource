import XCTest
@testable import AICoven

final class AnyJSONValueTests: XCTestCase {

    func testDecodeScalarsAndContainers() throws {
        let json = """
        {
          "string": "hello",
          "int": 42,
          "double": 3.5,
          "bool": true,
          "dict": { "a": 1, "b": "x" },
          "array": [1, "two", true],
          "nullValue": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let root = try decoder.decode([String: AnyJSONValue].self, from: json)

        XCTAssertEqual(root["string"]?.value as? String, "hello")
        XCTAssertEqual(root["int"]?.value as? Int, 42)
        XCTAssertEqual(root["double"]?.value as? Double, 3.5)
        XCTAssertEqual(root["bool"]?.value as? Bool, true)

        if let dict = root["dict"]?.value as? [String: AnyJSONValue] {
            XCTAssertEqual(dict["a"]?.value as? Int, 1)
            XCTAssertEqual(dict["b"]?.value as? String, "x")
        } else {
            XCTFail("Expected dict to decode as [String: AnyJSONValue]")
        }

        if let array = root["array"]?.value as? [AnyJSONValue] {
            XCTAssertEqual(array[0].value as? Int, 1)
            XCTAssertEqual(array[1].value as? String, "two")
            XCTAssertEqual(array[2].value as? Bool, true)
        } else {
            XCTFail("Expected array to decode as [AnyJSONValue]")
        }

        XCTAssertTrue(root["nullValue"]?.value is NSNull)
    }

    func testEncodeRoundTrip() throws {
        let original: [String: AnyJSONValue] = [
            "string": AnyJSONValue("hello"),
            "int": AnyJSONValue(42),
            "double": AnyJSONValue(3.5),
            "bool": AnyJSONValue(true),
            "dict": AnyJSONValue([
                "nested": AnyJSONValue("value"),
                "flag": AnyJSONValue(false)
            ]),
            "array": AnyJSONValue([
                AnyJSONValue("a"),
                AnyJSONValue(1),
                AnyJSONValue(true)
            ])
        ]

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([String: AnyJSONValue].self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
