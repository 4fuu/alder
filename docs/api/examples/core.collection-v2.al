fn append(values: mut Vec(U8), value: U8) -> Result(Unit, CapacityError) {
    return values.try_push(value)
}

fn bytes(values: Vec(U8)) -> Result(Bytes, CapacityError) {
    return Bytes.try_from_vec(values)
}
