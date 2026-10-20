// Counts how many pages got painted and shows it on the toolbar button
browser.runtime.onMessage.addListener(async (message) => {
  if (message !== "painted") return;
  const { count = 0 } = await browser.storage.local.get("count");
  await browser.storage.local.set({ count: count + 1 });
  await browser.action.setBadgeText({ text: String(count + 1) });
});
