extends Node
#Depends on the interpreter to tell it how much to read when

@onready var Interpreter = %Interpreter

@export_dir var export_dir := "res://"

signal read_finished()
signal write_finished()

func write_binary(what : PackedByteArray, filename : String):
	var outputfile = FileAccess.open(export_dir+filename+".bin", FileAccess.WRITE)
	for i in what.size():
		outputfile.store_8(what[i])
	outputfile.close()
	emit_signal("write_finished")

func read_binary(what : String):
	if !FileAccess.file_exists(what):
		printerr("Err: Binary file not found !")
		return
	
	var inputfile = FileAccess.open(what, FileAccess.READ)
	var eof_reached := false
	var bytes_read := 0
	while !eof_reached: #should loop until every layer is read
		if (inputfile.get_length()-bytes_read) < 4:
			print("loop err")
			printerr("Err: 4B requested but only %dB left in file !" % [inputfile.get_length()-bytes_read])
			break
		
		bytes_read += 4
		var bytes_needed = Interpreter.decode_layerdata(inputfile.get_buffer(4))
		if bytes_needed > inputfile.get_length()-bytes_read:
			print("length err")
			printerr("Err: %dB requested but only %dB left in file !" % [bytes_needed, inputfile.get_length()-bytes_read])
			break
		
		bytes_read += bytes_needed
		Interpreter.decode_tiledata(inputfile.get_buffer(bytes_needed))
		
		inputfile.get_8() #need to go past the file limits in order to check for EOF
		if inputfile.eof_reached():
			eof_reached = true
		else:
			inputfile.seek(inputfile.get_position()-8) #i dont feel like adding spacer bytes, so go back 8 bits
	inputfile.close()
	emit_signal("read_finished")

#exports the currently loaded tilemap w/ the help of the interpreter
#doesnt technically need its own func, but its niceys to have
func export_tilemap(filename := "tilemap-export"):
	if Interpreter.loaded_layers.size() > 0:
		write_binary(Interpreter.encode_tilemap_bin(), filename)
	else:
		printerr("Err: no tilemap loaded !")
		return
