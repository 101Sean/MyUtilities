import AppIntents
import Foundation

struct ConvertCSVToJSONIntent: AppIntent {
    static var title: LocalizedStringResource = "Convert CSV to JSON"
    static var description = IntentDescription("Converts CSV formatted text into JSON formatted text. The first line of the CSV should be the header.")

    @Parameter(title: "CSV Text")
    var csvText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Convert CSV text: \(\.$csvText)")
    }
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let jsonText = csvToJson(csvText: csvText) else {
            throw NSError(domain: "CSVConversionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "CSV Conversion failed. Please ensure the CSV is properly formatted."])
        }
        return .result(value: jsonText)
    }
    
    func csvToJson(csvText: String) -> String? {
        let lines = csvText.components(separatedBy: CharacterSet.newlines).filter { !$0.isEmpty }
        guard let headerLine = lines.first else {
            return nil
        }
        
        let headers = headerLine.components(separatedBy: ",")
        
        var jsonArray: [[String: String]] = []
        
        // 헤더 이후의 각 행 순회
        for line in lines.dropFirst() {
            let values = line.components(separatedBy: ",")
            // 행의 열 개수가 헤더와 일치하지 않으면 스킵
            if values.count != headers.count {
                continue
            }
            var jsonObject: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                // 앞뒤 공백 제거
                let key = header.trimmingCharacters(in: .whitespaces)
                let value = values[index].trimmingCharacters(in: .whitespaces)
                jsonObject[key] = value
            }
            jsonArray.append(jsonObject)
        }
        
        // JSONSerialization을 사용해 배열을 JSON 데이터로 변환
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonArray, options: .prettyPrinted)
            let jsonString = String(data: data, encoding: .utf8)
            return jsonString
        } catch {
            print("Error converting to JSON: \(error)")
            return nil
        }
    }
}
