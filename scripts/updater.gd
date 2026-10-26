extends Node
## Keeps installed copies up to date. On start it reads version.json from the latest GitHub Release.
## Windows: downloads the new TrueNorthCommand.exe next to the running one and swaps it in, so the next
## start is the new version. Android and Mac: shows an Update button that downloads the new app.
## The web version is always the latest. Builds made outside CI (version 1.0.0) never check.

signal update_available(url: String)
signal update_installed(version: String)

const BASE := "https://github.com/fisbal/true-north-command/releases/latest/download/"

var http: HTTPRequest
var latest := ""


static func build_of(version: String) -> int:
	var parts := version.split(".")
	return int(parts[parts.size() - 1]) if parts.size() >= 3 else 0


func _ready() -> void:
	_clean_old_exe()
	var mine := build_of(str(ProjectSettings.get_setting("application/config/version", "")))
	if mine <= 0 or OS.has_feature("web") or not OS.has_feature("template"):
		return
	http = HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)
	http.request_completed.connect(_on_version.bind(mine), CONNECT_ONE_SHOT)
	http.request(BASE + "version.json")


func _on_version(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, mine: int) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return  # offline: play on
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary) or int(data.get("build", 0)) <= mine:
		return
	latest = str(data.get("version", ""))
	if OS.has_feature("windows"):
		_download_exe()
	elif OS.has_feature("android"):
		update_available.emit(BASE + "TrueNorthCommand.apk")
	else:
		update_available.emit(BASE + "TrueNorthCommand-mac.zip")


func _download_exe() -> void:
	var exe := OS.get_executable_path()
	http.download_file = exe.get_base_dir().path_join("TrueNorthCommand.new.exe")
	http.request_completed.connect(_on_exe.bind(exe), CONNECT_ONE_SHOT)
	http.request(BASE + "TrueNorthCommand.exe")


func _on_exe(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray, exe: String) -> void:
	var fresh := http.download_file
	http.download_file = ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or FileAccess.get_file_as_bytes(fresh).size() < 1000000:
		DirAccess.remove_absolute(fresh)
		update_available.emit(BASE + "TrueNorthCommand.exe")  # could not write here: offer the download
		return
	# Windows lets a running program be renamed, not overwritten: move it aside, put the new one in its place.
	var old := exe.get_basename() + ".old.exe"
	DirAccess.remove_absolute(old)
	if DirAccess.rename_absolute(exe, old) != OK:
		DirAccess.remove_absolute(fresh)
		update_available.emit(BASE + "TrueNorthCommand.exe")
		return
	if DirAccess.rename_absolute(fresh, exe) != OK:
		DirAccess.rename_absolute(old, exe)
		update_available.emit(BASE + "TrueNorthCommand.exe")
		return
	update_installed.emit(latest)


func _clean_old_exe() -> void:
	if OS.has_feature("windows") and OS.has_feature("template"):
		var old := OS.get_executable_path().get_basename() + ".old.exe"
		if FileAccess.file_exists(old):
			DirAccess.remove_absolute(old)
