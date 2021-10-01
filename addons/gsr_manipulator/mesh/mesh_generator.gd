extends Object


static func add_rectangle(arr, v1, v2, v3, v4):
	arr.append(v1)
	arr.append(v2)
	arr.append(v3)
	arr.append(v3)
	arr.append(v4)
	arr.append(v1)


static func add_block(arr, v1, v2, v3, v4, l):
	add_rectangle(arr, v1, v2, v3, v4)
	add_rectangle(arr, v2, v1, v1 + l, v2 + l)
	add_rectangle(arr, v4, v3, v3 + l, v4 + l)
	add_rectangle(arr, v1, v4, v4 + l, v1 + l)
	add_rectangle(arr, v3, v2, v2 + l, v3 + l)
	add_rectangle(arr, v4 + l, v3 + l, v2 + l, v1 + l)
