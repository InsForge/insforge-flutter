/// A function definition exposed to the model as a callable tool.
class ToolFunction {
  const ToolFunction({
    required this.name,
    this.description,
    this.parameters,
  });

  final String name;
  final String? description;

  /// JSON-Schema object describing the function parameters.
  final Map<String, dynamic>? parameters;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        if (description != null) 'description': description,
        if (parameters != null) 'parameters': parameters,
      };

  factory ToolFunction.fromJson(Map<String, dynamic> json) => ToolFunction(
        name: json['name'].toString(),
        description: json['description']?.toString(),
        parameters: json['parameters'] is Map<String, dynamic>
            ? json['parameters'] as Map<String, dynamic>
            : null,
      );
}

/// A tool the model may call. Currently OpenAI/OpenRouter only define
/// `type: 'function'`.
class Tool {
  const Tool({required this.function, this.type = 'function'});

  final String type;
  final ToolFunction function;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'function': function.toJson(),
      };

  factory Tool.fromJson(Map<String, dynamic> json) => Tool(
        type: (json['type'] ?? 'function').toString(),
        function:
            ToolFunction.fromJson(json['function'] as Map<String, dynamic>),
      );
}

/// The function name + JSON-string arguments the model decided to call.
class ToolCallFunction {
  const ToolCallFunction({required this.name, required this.arguments});

  final String name;

  /// Arguments serialized as a JSON string (per OpenAI's contract).
  final String arguments;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'arguments': arguments,
      };

  factory ToolCallFunction.fromJson(Map<String, dynamic> json) =>
      ToolCallFunction(
        name: (json['name'] ?? '').toString(),
        arguments: (json['arguments'] ?? '').toString(),
      );
}

/// A tool call returned by the model in a response/delta.
class ToolCall {
  const ToolCall({
    required this.id,
    required this.function,
    this.type = 'function',
    this.index,
  });

  final String id;
  final String type;
  final ToolCallFunction function;

  /// Present in streaming deltas to identify parallel tool calls.
  final int? index;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'function': function.toJson(),
        if (index != null) 'index': index,
      };

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
        id: (json['id'] ?? '').toString(),
        type: (json['type'] ?? 'function').toString(),
        function:
            ToolCallFunction.fromJson(json['function'] as Map<String, dynamic>),
        index: json['index'] is int ? json['index'] as int : null,
      );
}

/// Controls which tool the model may call. Serializes to either a bare string
/// (`'auto'`, `'none'`, `'required'`) or a function-forcing object.
class ToolChoice {
  const ToolChoice._(this._value);

  final Object _value;

  static const ToolChoice auto = ToolChoice._('auto');
  static const ToolChoice none = ToolChoice._('none');
  static const ToolChoice required = ToolChoice._('required');

  /// Force the model to call the named function.
  factory ToolChoice.function(String name) => ToolChoice._(<String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{'name': name},
      });

  /// The JSON value (String or Map) to embed under `tool_choice`.
  Object toJson() => _value;
}
