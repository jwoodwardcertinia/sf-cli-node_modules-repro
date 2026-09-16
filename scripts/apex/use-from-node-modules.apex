// Demonstrates how the missing class actually bites in practice: not at
// deploy time, but later, when something references the type.
//
//   sf apex run -f scripts/apex/use-from-node-modules.apex
//
// Expected while the bug is present:
//
//   Error (executeCompileFailure): Compilation failed at Line 10 column 14
//   with the error: Variable does not exist: FromNodeModules
//
// even though the deploy that was supposed to create the class reported
// Status: Succeeded.

System.debug(FromNodeModules.whereAmI());
