extends Node2D
##handles conversions, mainly int-->bin, and execution
#rough comp ratios*: base=1.59 (62.8%), flag2=2.38 (41.8%)
#*only counting tiledata, actual figure will very likely change on export, comes with restrictions on tilemap & level size

@onready var FileIO = %"File IO"
@onready var Interpreter = %Interpreter

var testdata := PackedByteArray([1,13,1,5,1,1,2,3,3,1,3,2,4,4,2,4,5,4])

func _ready():
	FileIO.read_binary("res://resource-conversion.bin")
	await(get_tree().process_frame)
	Interpreter.convert_bin_node()

#debug purposes only
func rand_data_test(layer_count := 1, output_name := "rand", mode := "000"):
	var time = Time.get_unix_time_from_system()
	print("randstart")
	var rand_data = PackedByteArray([])
	for l in layer_count:
		randomize()
		var layer_length = randi_range(0,512)
		var layer_bytes = uint_to_bin(layer_length,16)
		rand_data.append_array([randi_range(0,255),bin_to_uint(uint_to_bin(randi_range(0,31))+mode),bin_to_uint(layer_bytes.left(8)),bin_to_uint(layer_bytes.right(8))])
		for i in layer_length:
			if mode == "010":
				rand_data.append_array([randi_range(0,255),randi_range(0,255)])
			else:
				rand_data.append_array([randi_range(0,255),randi_range(0,255),randi_range(0,255)])
			if i % 1000 == 999: #anti lagspike, prob overkill but whatever
				await(get_tree().process_frame)
	print("randend, created %s entries in %ss" % [rand_data.size(), round((Time.get_unix_time_from_system()-time)*100)/100])
	FileIO.write_binary(rand_data, output_name)

#bit0==1?i<0, range=-128->127 (num < 128 == negative)
func twos_compliment(num, bits := 8): #retruns a string of bits, only accepts strings or ints
	if typeof(num) == TYPE_STRING:
		var byte := ""
		for i in bits:
			byte += "1" if num.left(i+1).ends_with("0") else "0"
		return uint_to_bin(bin_to_uint(byte)+1, bits)
	elif typeof(num) == TYPE_INT:
		return uint_to_bin((num^255)+1)
	else:
		printerr("Err: expected type STRING or INT.")

#req knowing the amount of bits ahead of time, returns str (to preserve 0s)
func uint_to_bin(num : int, bits := 8):
	var byte := ""
	var current_div = num
	for i in bits:
		byte = String.num_uint64(current_div % 2) + byte
		@warning_ignore("integer_division") #always an even number when div
		current_div = (current_div - current_div % 2) / 2
		if current_div == 0:
			if i + 1 < bits:
				byte = "0".pad_zeros(bits-i-1) + byte
			break
	return byte

#uses a table to avoid doing a shit ton of pow operations, max of 16 bits
const BITVAL := [1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768,65536]
func bin_to_uint(bin : String):
	if bin.length() > 16:
		printerr("Err: too many bits (max 16), but got %d !" % bin.length())
		return
	var bits = bin.length()
	var num = 0
	var bin_split = bin.split()
	for i in bits:
		num += bin_split[bits-i-1].to_int()*BITVAL[i]
	return num
