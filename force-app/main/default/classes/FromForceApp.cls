/**
 * Ordinary class in an ordinary package directory. Control for the demo:
 * this one deploys, which proves the deploy itself worked and the org is
 * reachable. If you see this class in the org but not FromNodeModules,
 * the node_modules exclusion is what is biting.
 */
public with sharing class FromForceApp {
    public static String whereAmI() {
        return 'I was deployed from force-app';
    }
}
