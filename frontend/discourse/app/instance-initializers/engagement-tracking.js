export default {
  after: "inject-objects",

  initialize(owner) {
    const siteSettings = owner.lookup("service:site-settings");
    if (!siteSettings.persist_browser_pageview_events) {
      return;
    }

    owner.lookup("service:engagement-tracker").start();
  },
};
