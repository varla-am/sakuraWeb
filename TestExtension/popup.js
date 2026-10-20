document.getElementById("paint").addEventListener("click", async () => {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  await browser.scripting.insertCSS({
    target: { tabId: tab.id },
    css: "html { filter: sepia(0.4) hue-rotate(290deg) saturate(1.6) !important; }"
  });
  await browser.runtime.sendMessage("painted");
  document.getElementById("status").textContent = "Painted: " + tab.title;
});
