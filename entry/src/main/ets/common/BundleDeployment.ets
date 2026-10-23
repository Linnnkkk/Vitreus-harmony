// Share only the in-flight deployment across route instances. Never cache a
// completed result: every later call must recheck the bundle version on disk.
export class BundleDeployment {
  private static pending: Promise<string> | null = null;

  static run(deploy: () => Promise<string>): Promise<string> {
    if (BundleDeployment.pending !== null) { return BundleDeployment.pending; }
    BundleDeployment.pending = Promise.resolve().then(deploy).finally(() => {
      BundleDeployment.pending = null;
    });
    return BundleDeployment.pending;
  }
}
