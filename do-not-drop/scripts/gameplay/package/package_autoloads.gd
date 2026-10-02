class_name PackageAutoloads
extends RefCounted
## The autoloads a package talks to, looked up by path. A node outside the tree
## gets null, like a missing autoload. Kept out of package.gd, which is at the
## file-length limit (N-224.4).
##
## The network is typed as NetSession, the class NetworkManager extends: a
## renamed method or signal fails to compile, and `as` gives null if the node is
## not a session (test_dynamic_dispatch_budget checks it is). The other three
## stay plain nodes on purpose: preloading their scripts to type them makes any
## script that names DeliveryPackage compile them before the autoloads exist
## (run_manager.gd: "Identifier not found: EventBus", and the autoload then
## fails to load), and route_event_manager.gd names DeliveryPackage while
## crew_progression.gd preloads it, a cycle on top of that. RunManager has no
## class name to use instead (it would hide the autoload).


static func network(from: Node) -> NetSession:
	return (from.get_node_or_null(^"/root/NetworkManager") as NetSession) if from.is_inside_tree() else null


static func run_manager(from: Node) -> Node:
	return from.get_node_or_null(^"/root/RunManager") if from.is_inside_tree() else null


static func crew(from: Node) -> Node:
	return from.get_node_or_null(^"/root/CrewProgression") if from.is_inside_tree() else null


static func routes(from: Node) -> Node:
	return from.get_node_or_null(^"/root/RouteEventManager") if from.is_inside_tree() else null
