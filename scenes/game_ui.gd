extends Control

@onready var message_list: VBoxContainer = $MainLayout/ChatArea/MessageList
@onready var input: LineEdit = $MainLayout/InputBar/Input
@onready var server: AIServer = $AIServer
@onready var character_name: Label = $MainLayout/TopBar/CharacterName

@onready var whisper = $SpeechToText
@onready var mic_player = $MicPlayer

var voices = DisplayServer.tts_get_voices_for_language("en")
#safety check
var voice_id = voices[0] if not voices.is_empty() else ""

var chat_history: Array = []
var char_name: String = ""

var all_characters = []

func _ready() -> void:
	server.response_received.connect(_on_ai_reply)
	
	input.text_submitted.connect(_on_send_pressed)
	if has_node("MainLayout/InputBar/SendButton"):
		$MainLayout/InputBar/SendButton.pressed.connect(_on_send_pressed)
	
	if FileAccess.file_exists("res://Character.json"):
		var file = FileAccess.open("res://Character.json", FileAccess.READ)
		var json_text = file.get_as_text()
		all_characters = JSON.parse_string(json_text)
	
	setup_character_prompt("8da2d7bd-58a9-4101-8c40-d6111d7880e1")
	
	if whisper:
		whisper.transcribed_msg.connect(_on_whisper_transcribed)
	
func setup_character_prompt(character_id: String):
	var char_data = {}
	# Find the specific character in the JSON list with the given id
	for item in all_characters:
		if item["id"] == character_id:
			char_data = item["data"]
			break

	if char_data.is_empty():
		push_error("Character ID not found")
		return
	
	# Setting the name of the character
	char_name = char_data.get("name", "N/A")
	character_name.text = char_name

	# Building the system prompt
	var prompt = "You are an actor playing the role of %s in a murder mystery game.\n" % char_name
	prompt += "Role: %s\nBackstory: %s\nAlibi: %s\nMotivations: %s\nSECRET: %s\n" % [
		char_data.get("role", "N/A"),
		char_data.get("backstory", "N/A"),
		char_data.get("alibi", "N/A"),
		char_data.get("motivations", "N/A"),
		char_data.get("secrets", "N/A"),
	]
	prompt += "\nINSTRUCTIONS:\n1. Stay in character.\n2. Do not reveal secrets easily.\n3. Keep responses under 4 sentences."
	
	chat_history = [{"role": "system", "content": prompt}]
	
	# Making the character introduce himself/herself
	chat_history.append({"role": "user", "content": "Begin the scene. Introduce yourself and ask why I am here."})
	server.send_prompt(chat_history, "llama3")

# Sending the message to the AI as a prompt
func _send_to_server(text: String, is_player: bool = false):
	DisplayServer.tts_stop()
	
	if is_player:
		chat_history.append({"role": "user", "content": text})
		_add_bubble("You", text)
	
	input.editable = false
	server.send_prompt(chat_history, "llama3")

# Getting a message back. Also this is a signal
func _on_ai_reply(content: String):
	DisplayServer.tts_stop()
	input.editable = true
	chat_history.append({"role": "assistant", "content": content})
	_add_bubble(char_name, content)
	
	if voice_id != "":
		DisplayServer.tts_speak(content, voice_id)
	
	# Bringing the scroller to the most recent messages
	await get_tree().process_frame
	var scroll = $MainLayout/ChatArea
	if scroll is ScrollContainer:
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

# Adding the message to the chat
func _add_bubble(sender: String, text: String):
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = "[b]%s:[/b] %s" % [sender, text]
	label.fit_content = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_list.add_child(label)
	
func _on_send_pressed(_text_ignore = ""):
	var text = input.text.strip_edges()
	if text == "": return
	
	input.text = ""
	_send_to_server(text, true)

func _on_whisper_transcribed(is_final: bool, new_text: String):
	print("Whisper Signal: ", is_final, " TEXT: ", new_text)
	if is_final:
		var text = new_text.strip_edges()
		if text.length() > 2:
			DisplayServer.tts_stop()
			_process_voice_input(text)

func _process_voice_input(text: String):
	DisplayServer.tts_stop()
	input.text = "" 
	_send_to_server(text, true)

func _input(event: InputEvent) -> void:
	if input.has_focus():
		return
	
	if event is InputEventKey and event.keycode == KEY_CTRL and event.location == KEY_LOCATION_RIGHT:
		
		if event.is_pressed() and not event.is_echo():
			if not mic_player.playing:
				mic_player.play()
				DisplayServer.tts_stop()
				input.placeholder_text = "Listening... (Release Right-Ctrl to send)"
			
		elif not event.is_pressed():
			if mic_player.playing:
				await get_tree().create_timer(0.8).timeout
				mic_player.stop()
				input.placeholder_text = "Hold Right-Ctrl to talk..."
