import Foundation
import Observation

struct ParsedTask: Codable {
    let title: String
    let detail: String?
    let category: String?
    let priority: String?
    let dueDate: String?
}

@MainActor
@Observable
final class LLMService {
    var config: LLMConfig

    init(config: LLMConfig) {
        self.config = config
    }

    func parseFromText(_ text: String) async throws -> ParsedTask {
        let adapter = config.textAdapter
        guard let apiKey = KeychainHelper.loadString(key: adapter.keychainKey) else {
            GripLogger.shared.error("文本识别失败: API Key 未配置")
            throw LLMError.apiKeyNotConfigured
        }
        GripLogger.shared.info("开始文本识别，模型: \(adapter.model)，文本长度: \(text.count)")
        return try await callLLM(requestKind: "text", adapter: adapter, apiKey: apiKey, messages: [
            ["role": "user", "content": text]
        ])
    }

    func parseFromImage(_ imageData: Data) async throws -> ParsedTask {
        let adapter = config.imageAdapter
        guard let apiKey = KeychainHelper.loadString(key: adapter.keychainKey) else {
            GripLogger.shared.error("图片识别失败: API Key 未配置")
            throw LLMError.apiKeyNotConfigured
        }
        GripLogger.shared.info("开始图片识别，模型: \(adapter.model)，图片大小: \(imageData.count) bytes")
        let base64Image = imageData.base64EncodedString()
        let content: [[String: Any]] = [
            [
                "type": "image_url",
                "image_url": ["url": "data:image/png;base64,\(base64Image)"]
            ],
            [
                "type": "text",
                "text": "请从这张截图中提取待办任务"
            ]
        ]
        return try await callLLM(requestKind: "image", adapter: adapter, apiKey: apiKey, messages: [
            ["role": "user", "content": content]
        ])
    }

    private func callLLM(
        requestKind: String,
        adapter: LLMAdapterConfig,
        apiKey: String,
        messages: [[String: Any]]
    ) async throws -> ParsedTask {
        let endpoint = resolveEndpoint(adapter.apiURL)
        guard let url = URL(string: endpoint) else {
            GripLogger.shared.error("LLM 请求失败: URL 无效 - \(endpoint)")
            throw LLMError.invalidURL
        }

        let requestID = UUID().uuidString
        GripLogger.shared.info("LLM 请求开始[\(requestID)]: type=\(requestKind), endpoint=\(endpoint), model=\(adapter.model)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemMsg: [String: String] = [
            "role": "system",
            "content": systemPrompt()
        ]
        var allMessages: [[String: Any]] = [systemMsg]
        for msg in messages {
            allMessages.append(msg)
        }

        let body: [String: Any] = [
            "model": adapter.model,
            "messages": allMessages,
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        GripLogger.shared.debug("LLM 请求体[\(requestID)]: size=\(request.httpBody?.count ?? 0) bytes, messages=\(allMessages.count)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            GripLogger.shared.error("LLM 网络请求失败[\(requestID)]: type=\(requestKind), endpoint=\(endpoint), model=\(adapter.model), error=\(error.localizedDescription)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let headers = responseHeadersSummary(response as? HTTPURLResponse)
            let responseBody = responseBodySummary(data)
            GripLogger.shared.error("""
            LLM 请求失败[\(requestID)]:
            type=\(requestKind)
            endpoint=\(endpoint)
            model=\(adapter.model)
            status=\(statusCode)
            headers=\(headers)
            responseBody=\(responseBody)
            """)
            throw LLMError.httpError(statusCode, responseBody)
        }

        GripLogger.shared.debug("LLM 响应成功[\(requestID)]，大小: \(data.count) bytes")
        do {
            let parsed = try parseResponse(data)
            GripLogger.shared.info("LLM 解析成功[\(requestID)]: title=\(parsed.title), priority=\(parsed.priority ?? "nil"), dueDate=\(parsed.dueDate ?? "nil")")
            return parsed
        } catch {
            GripLogger.shared.error("""
            LLM 响应解析失败[\(requestID)]:
            type=\(requestKind)
            endpoint=\(endpoint)
            model=\(adapter.model)
            responseBody=\(responseBodySummary(data))
            error=\(error.localizedDescription)
            """)
            throw error
        }
    }

    private func resolveEndpoint(_ apiURL: String) -> String {
        let url = apiURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if url.hasSuffix("/chat/completions") {
            return url
        }
        return url + "/chat/completions"
    }

    private func parseResponse(_ data: Data) throws -> ParsedTask {
        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw LLMError.emptyResponse
        }

        let jsonStr = extractJSON(from: content)
        let jsonData = Data(jsonStr.utf8)
        return try JSONDecoder().decode(ParsedTask.self, from: jsonData)
    }

    private func extractJSON(from text: String) -> String {
        let pattern = "```(?:json)?\\s*\\n?([\\s\\S]*?)\\n?```"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func responseHeadersSummary(_ response: HTTPURLResponse?) -> String {
        guard let response else { return "nil" }
        let interestingKeys = [
            "retry-after",
            "x-request-id",
            "x-ratelimit-limit-requests",
            "x-ratelimit-remaining-requests",
            "x-ratelimit-reset-requests",
            "x-ratelimit-limit-tokens",
            "x-ratelimit-remaining-tokens",
            "x-ratelimit-reset-tokens"
        ]

        var values: [String] = []
        for key in interestingKeys {
            if let value = headerValue(response: response, key: key) {
                values.append("\(key)=\(value)")
            }
        }

        if values.isEmpty {
            values.append("all=\(response.allHeaderFields)")
        }
        return values.joined(separator: ", ")
    }

    private func headerValue(response: HTTPURLResponse, key: String) -> String? {
        for (headerKey, headerValue) in response.allHeaderFields {
            guard String(describing: headerKey).lowercased() == key else { continue }
            return String(describing: headerValue)
        }
        return nil
    }

    private func responseBodySummary(_ data: Data, limit: Int = 4_000) -> String {
        guard !data.isEmpty else { return "<empty>" }
        let raw = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        let normalized = raw.replacingOccurrences(of: "\n", with: "\\n")
        if normalized.count <= limit {
            return normalized
        }
        return String(normalized.prefix(limit)) + "...<truncated \(normalized.count - limit) chars>"
    }

    private func systemPrompt() -> String {
        let dfFull = DateFormatter()
        dfFull.dateFormat = "yyyy-MM-dd HH:mm"
        let dfDay = DateFormatter()
        dfDay.dateFormat = "yyyy-MM-dd"
        let now = dfFull.string(from: Date())
        let today = dfDay.string(from: Date())
        return """
        你是一个任务提取助手。用户会给你一段文字或截图，你需要从中提取出一个待办任务。

        当前时间：\(now)
        今天日期：\(today)

        返回 JSON 格式，字段如下：
        {
          "title": "简洁的任务标题（不超过 50 字，动宾结构，如「完成汇报 PPT」）",
          "detail": "补充描述或上下文（没有则为 null）",
          "category": "分类，只能填：工作、学习、生活、其他（无法判断填「其他」）",
          "priority": "优先级，只能填：none、low、medium、high（有紧急/重要/尽快等关键词时提升优先级）",
          "dueDate": "截止时间，格式 YYYY-MM-DD HH:mm（无具体时间用 YYYY-MM-DD，无法推断则为 null）"
        }

        规则：
        1. dueDate 解析规则：
           - 「今晚11点」「晚上11点前」→ 今天的 23:00，格式 YYYY-MM-DD HH:mm
           - 「明天下午3点」→ 明天的 15:00
           - 「下周一」→ 下一个周一的日期
           - 「本周五前」→ 本周五的日期
           - 只有日期没有时间 → 只填 YYYY-MM-DD
           - 无法推断时间 → null
        2. 有「紧急」「尽快」「马上」「立即」等词 → priority 设为 high
        3. 有「重要」「记得」「别忘了」等词 → priority 至少 medium
        4. title 要简洁明确，去掉语气词和冗余表达
        5. 只返回 JSON，不要其他文字
        """
    }
}

extension LLMService {
    func parseResponseTest(_ data: Data) throws -> ParsedTask {
        try parseResponse(data)
    }

    func parseFullResponseTest(_ data: Data) throws -> ParsedTask {
        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw LLMError.emptyResponse
        }
        let jsonStr = extractJSON(from: content)
        let jsonData = Data(jsonStr.utf8)
        return try JSONDecoder().decode(ParsedTask.self, from: jsonData)
    }
}

enum LLMError: LocalizedError {
    case apiKeyNotConfigured
    case invalidURL
    case httpError(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured: "API Key 未配置"
        case .invalidURL: "API URL 格式错误"
        case .httpError(let code, let body): "HTTP 错误: \(code)，响应: \(body)"
        case .emptyResponse: "LLM 返回为空"
        }
    }
}
