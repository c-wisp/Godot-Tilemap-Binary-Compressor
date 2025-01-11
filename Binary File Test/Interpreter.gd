extends Node
#encodes and decodes layerdata

@onready var Key = %Key

#tilemap settings
#offsetx : int2B
#offsety : int2B
#tileset : String64B

class layer:
	var tileset : int
	var layer : int
	var flag1 := false #3B/tile, compat w/ flag3, reserves 2b of the id for flip h/v
	var flag2 := false #2B/tile, splits 2B up; 6b for id, 5b for each pos
	var flag3 := false #unused, do as you wish with it
	var tilecount : int
	var tiledata : PackedVector3Array #x=id, yz=gridpos
	var flippedtilesh := PackedVector2Array([]) #sorted by position
	var flippedtilesv := PackedVector2Array([])

var loaded_layers := []

#Bin Exporter --> Bin Interpreter --> Bin Exporter
#mostly just init for layersettings
func decode_layerdata(data : PackedByteArray):
	if data.size() < 4:
		printerr("Err: expected 4B Array, but got %d !" % data.size())
		return
	var data_bin := PackedStringArray([])
	for i in 3:
		data_bin.append(owner.uint_to_bin(data[i+1],8))
	
	var newlayer = layer.new()
	newlayer.tileset = data[0]
	newlayer.layer = owner.bin_to_uint(data_bin[0].left(5))
	
	var byte_mult := 3
	if data_bin[0].right(3).begins_with("1"):
		newlayer.flag1 = true
	if data_bin[0].right(2).begins_with("1"):
		newlayer.flag2 = true
		byte_mult = 2
	if data_bin[0].ends_with("1"):
		newlayer.flag3 = true
		byte_mult = 5
	
	newlayer.tilecount = owner.bin_to_uint(data_bin[1]+data_bin[2])
	loaded_layers.append(newlayer)
	
	return newlayer.tilecount * byte_mult #pass back the amount of bytes needed to read the rest of the layer

func decode_tiledata(data : PackedByteArray):
	var current_layer := loaded_layers.size()-1
	var flag_passed := false
	var use_flag1 = loaded_layers[current_layer].flag1
	var temp := Vector3.ZERO
	
	if loaded_layers[current_layer].flag2: #2B/tile
		flag_passed = true
		var current_byte := 0
		while current_byte < data.size(): #000000 00000 00000 --> 00000|00 000|00000
			if current_byte % 1000 >= 998:
				await(get_tree().process_frame)
			#stupid as shit, but works
			temp.x = owner.bin_to_uint(owner.uint_to_bin(data[current_byte]).left(6))
			temp.y = owner.bin_to_uint(owner.uint_to_bin(data[current_byte]).right(2)+owner.uint_to_bin(data[current_byte+1]).left(3))
			temp.z = owner.bin_to_uint(owner.uint_to_bin(data[current_byte+1]).right(5))
			loaded_layers[current_layer].tiledata.append(temp)
			current_byte += 2
	
	if loaded_layers[current_layer].flag3: #custom (aka i have a spare bit and nothing to do with it)
		print_debug("NOTICE: this layer has flag3 enabled, however flag3 is not configured for anything. Default behavior will be used.")
	
	if !flag_passed: #default
		for byte in data.size():
			match byte % 3:
				0:
					temp.x = data[byte]
				1:
					temp.y = data[byte]
				2:
					temp.z = data[byte]
					
					if use_flag1:
						var byte_bin = owner.uint_to_bin(data[byte-2])
						var temp2 := Vector2(temp.y,temp.z)
						temp.x = owner.bin_to_uint(byte_bin.left(6))
						if byte_bin.right(7).begins_with("1"):
							loaded_layers[current_layer].flippedtilesh.append(temp2)
						if byte_bin.right(8).begins_with("1"):
							loaded_layers[current_layer].flippedtilesv.append(temp2)
					
					loaded_layers[current_layer].tiledata.append(temp)
			if byte % 1000 == 999:
				await(get_tree().process_frame)

#Interpreter --> FileIO
func encode_tilemap_bin():
	if loaded_layers.size() == 0:
		printerr("Err: encode what ??? [no layers loaded]")
		return
	var data = PackedByteArray([])
	for l in loaded_layers:
		l.flag2=false
		#append layersettings
		var temp = "1" if l.flag1 else "0"
		temp += "1" if l.flag2 else "0"
		temp += "1" if l.flag3 else "0"
		data.append_array([l.tileset, owner.bin_to_uint(owner.uint_to_bin(l.layer)+temp)])
		temp = owner.uint_to_bin(l.tilecount,16)
		data.append_array([owner.bin_to_uint(temp.left(8)), owner.bin_to_uint(temp.right(8))])
		
		#translate tiledata
		if l.flag1:
			for t in l.tiledata: #a little repetitive, but saves a lot of useless checks
				temp = "1" if l.flippedtilesh.has(Vector2(t.y,t.z)) else "0"
				temp += "1" if l.flippedtilesv.has(Vector2(t.y,t.z)) else "0"
				data.append_array([owner.bin_to_uint(owner.uint_to_bin(t.x).right(6)+temp), t.y, t.z])
		elif l.flag2:
			for t in l.tiledata:
				temp = owner.uint_to_bin(t.x).right(6)+owner.uint_to_bin(t.y).right(5)+owner.uint_to_bin(t.z).right(5)
				data.append_array([owner.bin_to_uint(temp.left(8)), owner.bin_to_uint(temp.right(8))])
		else:
			for t in l.tiledata:
				data.append_array([t.x,t.y,t.z])
	return data

#TilemapLayer Node --> TilemapLayer_Bin Node
func convert_tilemap_resource_bin(map : TileMap, flag1 := false, flag2 := false, flag3 := false):
	loaded_layers.clear()
	for l in map.get_layers_count():
		var binlayer := layer.new()
		var coords := map.get_used_cells(l)
		
		binlayer.layer = map.get_layer_z_index(l)
		binlayer.flag1 = flag1
		binlayer.flag2 = flag2
		binlayer.flag3 = flag3
		binlayer.tilecount = coords.size()
		
		#do some weird ass shite to get the cell's id (also tileset's id but ykyk)
		#this will be a pain to load later,.,.,
		var sourceid = map.get_cell_source_id(l,coords[0])
		var tilesetsource = map.tile_set.get_source(map.tile_set.get_source_id(sourceid))
		binlayer.tileset = sourceid
		
		for t in tilesetsource.get_tiles_count(): #tilelist
			var used_cells = map.get_used_cells_by_id(l, sourceid, tilesetsource.get_tile_id(t))
			for c in used_cells: #convert vec2 array --> layertiledata (vec3 array)
				binlayer.tiledata.append(Vector3(t,c.x,c.y))
				if flag1:
					var tiledata = map.get_cell_tile_data(l,c)
					if tiledata.flip_h:
						binlayer.flippedtilesh.append(c)
					if tiledata.flip_v:
						binlayer.flippedtilesv.append(c)
		
		loaded_layers.append(binlayer)
	print("Successfully converted %d layers into binary-compat layers !" % map.get_layers_count())
	print("flags -- %d:%d:%d" % [int(flag1),int(flag2),int(flag3)])

#loadedlayer --> tilemap node
func convert_bin_node():
	if loaded_layers.size() == 0:
		printerr("Err: No tilemap loaded !")
		return
	var tilemap := TileMap.new()
	for l in loaded_layers.size():
		tilemap.add_layer(-1)
		tilemap.set_layer_z_index(l,loaded_layers[l].layer)
		tilemap.tile_set = load(Key.tilesets[loaded_layers[l].tileset])
		var tilesetsource = tilemap.tile_set.get_source(loaded_layers[l].tileset)
		for c in loaded_layers[l].tiledata:
			tilemap.set_cell(-1,Vector2i(c.y,c.z),loaded_layers[l].tileset,tilesetsource.get_tile_id(c.x))
	owner.add_child(tilemap)
	print("binary tilemap loaded !")
