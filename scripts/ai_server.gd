extends Node
class_name AIServer

signal response_received(content: String)

var http_request: HTTPRequest
var api_key: String = ""
@export var use_local: bool = true # Toggle this for OpenAI or Ollama

func _ready():
	# Setting up HTTP stuff
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

# Sending a prompt depending on that model is used
func send_prompt(messages: Array, model: String):
	if use_local:
		_call_ollama(messages, model)
	else:
		_call_openai(messages, model)

# Sending the prompt to Ollama if local
func _call_ollama(messages, model):
	var url = "http://localhost:11434/api/chat"
	var body = {"model": model, "messages": messages, "stream": false}
	http_request.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))

# Sending the prompt to OpenAI
func _call_openai(messages, model):
	var url = "https://api.openai.com/v1/chat/completions"
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + api_key]
	var body = {"model": model, "messages": messages}
	http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

# Sending out a response once there is one through a signal
func _on_request_completed(_result, _code, _headers, body):
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null: return
	
	# OpenAI and Ollama has different structures
	var content = ""
	if json.has("message"): content = json["message"]["content"] # Ollama
	elif json.has("choices"): content = json["choices"][0]["message"]["content"] # OpenAI
	
	# Emitting the response as a signal
	response_received.emit(content)
