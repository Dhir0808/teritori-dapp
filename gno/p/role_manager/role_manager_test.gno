package role_manager

import (
	"std"
	"testing"

	"gno.land/p/demo/testutils"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
)

func TestNewWithAddress(t *testing.T) {
	rm := NewWithAddress(alice)
	if rm.owner.Owner() != alice {
		t.Fatalf("expected owner to be %s, got %s", alice, rm.owner.Owner())
	}
}

func TestDropOwnership(t *testing.T) {
	rm := NewWithAddress(alice)
	std.TestSetOrigCaller(alice)
	rm.GetOwner().DropOwnership()

	if rm.GetOwner().Owner() != std.Address("") {
		t.Fatalf("expected owner to be empty")
	}
}

func TestCreateNewRole(t *testing.T) {
	std.TestSetOrigCaller(alice)
	rm := NewWithAddress(alice)
	rm.CreateNewRole("role1", []string{"perm1", "perm2"})
	rm.CreateNewRole("role2", []string{"perm3", "perm4"})

	v, ok := rm.roles.Get("role1")
	if !ok {
		t.Fatalf("expected role1 to exist")
	}
	role1 := v.(*Role)
	v, ok = rm.roles.Get("role2")
	if !ok {
		t.Fatalf("expected role2 to exist")
	}
	role2 := v.(*Role)

	if role1.name != "role1" {
		t.Fatalf("expected role1 name to be role1, got %s", role1.name)
	}
	if !role1.permissions.Has("perm1") {
		t.Fatalf("expected role1 to have perm1")
	}
	if !role1.permissions.Has("perm2") {
		t.Fatalf("expected role1 to have perm2")
	}

	if role2.name != "role2" {
		t.Fatalf("expected role2 name to be role2, got %s", role2.name)
	}
	if !role2.permissions.Has("perm3") {
		t.Fatalf("expected role2 to have perm3")
	}
	if !role2.permissions.Has("perm4") {
		t.Fatalf("expected role2 to have perm4")
	}
}

func TestDeleteRole(t *testing.T) {
	std.TestSetOrigCaller(alice)
	rm := NewWithAddress(alice)
	rm.CreateNewRole("role1", []string{"perm1", "perm2"})
	rm.CreateNewRole("role2", []string{"perm3", "perm4"})

	rm.AddRoleToUser(alice, "role1")

	rm.DeleteRole("role1")

	if _, ok := rm.roles.Get("role1"); ok {
		t.Fatalf("expected role1 to be deleted")
	}

	if _, ok := rm.users.Get(alice.String()); !ok {
		t.Fatalf("expected user to still exist")
	}

	aliceRoles := rm.getUser(alice)
	if aliceRoles.Has("role1") {
		t.Fatalf("expected role1 to be removed from user")
	}
}

func TestAddPermissionToRole(t *testing.T) {
	std.TestSetOrigCaller(alice)
	rm := NewWithAddress(alice)
	rm.CreateNewRole("role1", []string{"perm1", "perm2"})
	rm.AddPermissionToRole("perm3", "role1")
	rm.AddRoleToUser(alice, "role1")

	v, ok := rm.roles.Get("role1")
	if !ok {
		t.Fatalf("expected role1 to exist")
	}
	role1 := v.(*Role)

	if !role1.permissions.Has("perm3") {
		t.Fatalf("expected role1 to have perm3")
	}

	aliceRoles := rm.getUser(alice)
	if !aliceRoles.Has("role1") {
		t.Fatalf("expected role1 to be added to user")
	}

	if !rm.HasPermission(alice, "perm3") {
		t.Fatalf("expected user to have perm3")
	}
}

func TestRemovePermissionFromRole(t *testing.T) {
	std.TestSetOrigCaller(alice)
	rm := NewWithAddress(alice)
	rm.CreateNewRole("role1", []string{"perm1", "perm2", "perm3"})

	rm.AddRoleToUser(alice, "role1")

	rm.RemovePermissionFromRole("perm3", "role1")

	v, ok := rm.roles.Get("role1")
	if !ok {
		t.Fatalf("expected role1 to exist")
	}
	role1 := v.(*Role)

	if role1.permissions.Has("perm3") {
		t.Fatalf("expected role1 to not have perm3")
	}

	aliceRoles := rm.getUser(alice)
	if !aliceRoles.Has("role1") {
		t.Fatalf("expected role1 to be added to user")
	}

	if rm.HasPermission(alice, "perm3") {
		t.Fatalf("expected user to not have perm3")
	}
}

func TestAddRoleToUser(t *testing.T) {
	std.TestSetOrigCaller(alice)
	rm := NewWithAddress(alice)
	rm.CreateNewRole("role1", []string{"perm1", "perm2"})
	rm.CreateNewRole("role2", []string{"perm3", "perm4"})
	rm.CreateNewRole("role3", []string{"perm5", "perm6"})

	rm.AddRoleToUser(alice, "role1")
	rm.AddRoleToUser(alice, "role2")
	rm.AddRoleToUser(alice, "role3")

	rm.RemoveRoleFromUser(alice, "role2")

	aliceRoles := rm.getUser(alice)
	if !aliceRoles.Has("role1") {
		t.Fatalf("expected role1 to be added to user")
	}
	if aliceRoles.Has("role2") {
		t.Fatalf("expected role2 to be removed from user")
	}
	if !aliceRoles.Has("role3") {
		t.Fatalf("expected role3 to be added to user")
	}
}

func TestRemoveRoleFromUser(t *testing.T) {
	std.TestSetOrigCaller(alice)
	rm := NewWithAddress(alice)
	rm.CreateNewRole("role1", []string{"perm1", "perm2"})
	rm.CreateNewRole("role2", []string{"perm3", "perm4"})
	rm.CreateNewRole("role3", []string{"perm5", "perm6"})

	rm.AddRoleToUser(alice, "role1")
	rm.AddRoleToUser(alice, "role2")
	rm.AddRoleToUser(alice, "role3")

	rm.RemoveRoleFromUser(alice, "role2")
	rm.RemoveRoleFromUser(alice, "role1")

	aliceRoles := rm.getUser(alice)
	if aliceRoles.Has("role1") {
		t.Fatalf("expected role1 to be removed from user")
	}
	if aliceRoles.Has("role2") {
		t.Fatalf("expected role2 to be removed from user")
	}
	if !aliceRoles.Has("role3") {
		t.Fatalf("expected role3 to be added to user")
	}
}

func TestHasPermission(t *testing.T) {
	std.TestSetOrigCaller(alice)
	rm := NewWithAddress(alice)
	rm.CreateNewRole("role1", []string{"perm1", "perm2"})
	rm.CreateNewRole("role2", []string{"perm3", "perm4"})
	rm.CreateNewRole("role3", []string{"perm5", "perm6"})

	rm.AddRoleToUser(alice, "role1")
	rm.AddRoleToUser(alice, "role2")
	rm.AddRoleToUser(alice, "role3")

	if !rm.HasPermission(alice, "perm1") {
		t.Fatalf("expected user to have perm1")
	}
	if !rm.HasPermission(alice, "perm3") {
		t.Fatalf("expected user to have perm3")
	}
	if !rm.HasPermission(alice, "perm5") {
		t.Fatalf("expected user to have perm5")
	}
	if rm.HasPermission(alice, "perm7") {
		t.Fatalf("expected user to not have perm7")
	}
}

func TestHasRole(t *testing.T) {
	std.TestSetOrigCaller(alice)
	rm := NewWithAddress(alice)
	rm.CreateNewRole("role1", []string{"perm1", "perm2"})
	rm.CreateNewRole("role2", []string{"perm3", "perm4"})
	rm.CreateNewRole("role3", []string{"perm5", "perm6"})

	rm.AddRoleToUser(alice, "role1")
	rm.AddRoleToUser(alice, "role2")
	rm.AddRoleToUser(alice, "role3")

	if !rm.HasRole(alice, "role1") {
		t.Fatalf("expected user to have role1")
	}
	if !rm.HasRole(alice, "role2") {
		t.Fatalf("expected user to have role2")
	}
	if !rm.HasRole(alice, "role3") {
		t.Fatalf("expected user to have role3")
	}
	if rm.HasRole(alice, "role4") {
		t.Fatalf("expected user to not have role4")
	}
}
