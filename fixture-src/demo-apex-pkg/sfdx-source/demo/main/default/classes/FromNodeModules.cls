/**
 * Ships inside an npm package, so after `npm install` it lives at
 * node_modules/demo-apex-pkg/sfdx-source/demo/main/default/classes/
 *
 * This is the class that should appear in the org but does not.
 */
public with sharing class FromNodeModules {
    public static String whereAmI() {
        return 'I was deployed from node_modules';
    }
}
