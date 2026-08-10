package verify

import "testing"

const tableHeader = `mir 1
type @P {
  x: i64
}
const @one: i64 = 1
`

func TestPhase8LookupAndMutation(t *testing.T) {
	t.Run("insert active", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @f(%t: table(@P), %id: id(@P), %p: @P) {
entry:
  %o = table.lookup %t, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  %new = table.insert %t, %p
  table.view.end %v
  return
none:
  return
}
`, "table mutation runs while a view")
	})

	t.Run("before extraction", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @f(%t: table(@P), %id: id(@P), %p: @P) {
entry:
  %o = table.lookup %t, %id
  %new = table.insert %t, %p
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  table.view.end %v
  return
none:
  return
}
`, "runs before lookup result")
	})

	t.Run("none mutation", func(t *testing.T) {
		requireAccepted(t, tableHeader+`
fn @f(%t: table(@P), %id: id(@P), %p: @P) {
entry:
  %o = table.lookup %t, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  table.view.end %v
  return
none:
  %new = table.insert %t, %p
  return
}
`)
	})

	t.Run("unconsumed", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @f(%t: table(@P), %id: id(@P)) {
entry:
  %o = table.lookup %t, %id
  return
}
`, "must be consumed exactly once")
	})

	t.Run("switch without some binding", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @f(%t: table(@P), %id: id(@P)) {
entry:
  %o = table.lookup %t, %id
  switch %o {
    some -> some
    none -> none
  }
some:
  return
none:
  return
}
`, "must be consumed exactly once")
	})

	t.Run("consumed twice", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @f(%t: table(@P), %id: id(@P)) {
entry:
  %o = table.lookup %t, %id
  %v1 = enum.payload.checked %o, some else failed
  table.view.end %v1
  %v2 = enum.payload.checked %o, some else failed
  table.view.end %v2
  return
failed:
  return
}
`, "must be consumed exactly once")
	})
}

func TestPhase8AliasCallAndCheckedExtraction(t *testing.T) {
	t.Run("block alias", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @f(%t: table(@P), %id: id(@P), %p: @P) {
entry:
  %o = table.lookup %t, %id
  switch %o {
    some(%v) -> some(%t)
    none -> none
  }
some(%alias: table(@P)):
  %new = table.insert %alias, %p
  table.view.end %v
  return
none:
  return
}
`, "table mutation runs while a view")
	})

	t.Run("callee", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @mutate(%t: table(@P), %p: @P) {
entry:
  %id = table.insert %t, %p
  return
}
fn @f(%t: table(@P), %id: id(@P), %p: @P) {
entry:
  %o = table.lookup %t, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  call @mutate(%t, %p)
  table.view.end %v
  return
none:
  return
}
`, "table mutation runs while a view")
	})

	t.Run("checked success and failure", func(t *testing.T) {
		requireAccepted(t, tableHeader+`
fn @f(%t: table(@P), %id: id(@P)) {
entry:
  %o = table.lookup %t, %id
  %v = enum.payload.checked %o, some else failed
  %x = load field(deref %v, x)
  table.view.end %v
  return
failed:
  return
}
`)
	})

	t.Run("returned parameter identity", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @pass(%t: table(@P)) -> table(@P) {
entry:
  return %t
}
fn @f(%t: table(@P), %id: id(@P), %p: @P) {
entry:
  %alias = call @pass(%t)
  %o = table.lookup %alias, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  %new = table.insert %t, %p
  table.view.end %v
  return
none:
  return
}
`, "table mutation runs while a view")
	})

	t.Run("cleanup callback mutation", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @mutate(%t: table(@P), %p: @P) {
entry:
  %id = table.insert %t, %p
  return
}
fn @f(%t: table(@P), %id: id(@P), %p: @P) {
entry:
  %o = table.lookup %t, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  %s = cleanup.scope.begin
  %e = cleanup.push %s, @mutate, (%t, %p)
  cleanup.scope.run %s
  cleanup.scope.end %s
  table.view.end %v
  return
none:
  return
}
`, "table mutation runs while a view")
	})

	t.Run("disarmed cleanup callback", func(t *testing.T) {
		requireAccepted(t, tableHeader+`
fn @mutate(%t: table(@P), %p: @P) {
entry:
  %id = table.insert %t, %p
  return
}
fn @f(%t: table(@P), %id: id(@P), %p: @P) {
entry:
  %o = table.lookup %t, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  %s = cleanup.scope.begin
  %e = cleanup.push %s, @mutate, (%t, %p)
  cleanup.disarm %e
  cleanup.scope.run %s
  cleanup.scope.end %s
  table.view.end %v
  return
none:
  return
}
`)
	})

	t.Run("recursive mutation summary", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @mutate_recursive(%t: table(@P), %p: @P, %stop: bool) {
entry:
  branch %stop, base, recur
base:
  %id = table.insert %t, %p
  return
recur:
  call @mutate_recursive(%t, %p, %stop)
  return
}
fn @f(%t: table(@P), %id: id(@P), %p: @P, %stop: bool) {
entry:
  %o = table.lookup %t, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  call @mutate_recursive(%t, %p, %stop)
  table.view.end %v
  return
none:
  return
}
`, "table mutation runs while a view")
	})

	t.Run("new table return has call-site identity", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @make(%d: domain_handle) -> table(@P) {
entry:
  %t = table.create @P, %d
  return %t
}
fn @f(%d: domain_handle, %id: id(@P), %p: @P) {
entry:
  %t = call @make(%d)
  %o = table.lookup %t, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  %new = table.insert %t, %p
  table.view.end %v
  return
none:
  return
}
`, "table mutation runs while a view")
	})
}

func TestPhase8CheckedFailurePaths(t *testing.T) {
	t.Run("before extraction", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @f(%t: table(@P), %id: id(@P), %a: i64) {
entry:
  %o = table.lookup %t, %id
  %sum = int.add.checked %a, %a else failed
  %v = enum.payload.checked %o, some else failed
  table.view.end %v
  return
failed:
  return
}
`, "may bypass consumption of table lookup result")
	})

	t.Run("before view end", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @f(%t: table(@P), %id: id(@P), %a: i64) {
entry:
  %o = table.lookup %t, %id
  %v = enum.payload.checked %o, some else absent
  %sum = int.add.checked %a, %a else overflow
  table.view.end %v
  return
overflow:
  return
absent:
  return
}
`, "may bypass table.view.end")
	})

	t.Run("after view end", func(t *testing.T) {
		requireAccepted(t, tableHeader+`
fn @f(%t: table(@P), %id: id(@P), %p: @P, %a: i64) {
entry:
  %o = table.lookup %t, %id
  %v = enum.payload.checked %o, some else absent
  table.view.end %v
  %sum = int.add.checked %a, %a else overflow
  return
overflow:
  %new = table.insert %t, %p
  return
absent:
  return
}
`)
	})
}

func TestPhase8ExternalAndNestedTableIdentity(t *testing.T) {
	t.Run("formal table parameters may alias", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @f(%left: table(@P), %right: table(@P), %id: id(@P), %p: @P) {
entry:
  %o = table.lookup %left, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  %new = table.insert %right, %p
  table.view.end %v
  return
none:
  return
}
`, "table mutation runs while a view")
	})

	t.Run("aggregate call result preserves parameter table", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
type @Holder {
  table: table(@P)
}
fn @wrap(%t: table(@P)) -> @Holder {
entry:
  %h = aggregate.construct @Holder { table: %t }
  return %h
}
fn @f(%t: table(@P), %id: id(@P), %p: @P) {
  local %slot: @Holder

entry:
  %h = call @wrap(%t)
  store local %slot, %h
  %alias = load field(local %slot, table)
  %o = table.lookup %alias, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  %new = table.insert %t, %p
  table.view.end %v
  return
none:
  return
}
`, "table mutation runs while a view")
	})

	t.Run("aggregate call result preserves local table", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
type @Holder {
  table: table(@P)
}
fn @make(%d: domain_handle) -> @Holder {
entry:
  %t = table.create @P, %d
  %h = aggregate.construct @Holder { table: %t }
  return %h
}
fn @f(%d: domain_handle, %id: id(@P), %p: @P) {
  local %slot: @Holder

entry:
  %h = call @make(%d)
  store local %slot, %h
  %t = load field(local %slot, table)
  %o = table.lookup %t, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  %new = table.insert %t, %p
  table.view.end %v
  return
none:
  return
}
`, "table mutation runs while a view")
	})

	t.Run("deref-loaded and direct parameters may alias", func(t *testing.T) {
		requireRejectedWith(t, tableHeader+`
fn @f(%slot: safe_ref(table(@P)), %direct: table(@P), %id: id(@P), %p: @P) {
entry:
  %loaded = load deref %slot
  %o = table.lookup %loaded, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  %new = table.insert %direct, %p
  table.view.end %v
  return
none:
  return
}
`, "table mutation runs while a view")
	})

	t.Run("distinct local tables", func(t *testing.T) {
		requireAccepted(t, tableHeader+`
fn @f(%d: domain_handle, %id: id(@P), %p: @P) {
entry:
  %left = table.create @P, %d
  %right = table.create @P, %d
  %o = table.lookup %left, %id
  switch %o {
    some(%v) -> some
    none -> none
  }
some:
  %new = table.insert %right, %p
  table.view.end %v
  return
none:
  return
}
`)
	})
}
