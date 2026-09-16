// Reports whether each demo class made it into the org.
//
// Deliberately uses Type.forName rather than referencing the classes
// directly, so that this block compiles whether or not they are present --
// a static reference to a missing class fails at compile time and tells you
// nothing about the other one.
//
//   sf apex run -f scripts/apex/check-classes.apex

for (String name : new List<String>{ 'FromForceApp', 'FromNodeModules' }) {
    Type t = Type.forName(name);
    System.debug(name + ' => ' + (t == null ? 'MISSING' : 'present'));
}
