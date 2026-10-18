/* Knobs website. No dependencies, no network requests. */

// The one place for outbound links. The repository isn't public yet; these are its future addresses.
const LINKS = {
  github: "https://github.com/deva0x/knobs",
  download: "https://github.com/deva0x/knobs/releases/latest",
  "manifest-docs": "https://github.com/deva0x/knobs/blob/main/docs/MANIFEST_FORMAT.md",
  license: "https://github.com/deva0x/knobs/blob/main/LICENSE",
};

// The Shrink a video task, as written in docs/MANIFEST_FORMAT.md. The demo builds its command from this.
const SHRINK_VIDEO = {
  executable: "ffmpeg",
  fields: {
    input: { kind: "inputFile" },
    size: { kind: "choice", default: "1280" },
    quality: { kind: "integer", default: 23, minimum: 18, maximum: 32 },
    mute: { kind: "toggle", default: false },
  },
  output: { template: "{input.stem} small.mp4" },
  arguments: [
    "-hide_banner", "-i", "{input}",
    { if: "size", then: ["-vf", "scale={size}:-2"] },
    "-crf", "{quality}",
    { if: "mute", then: ["-an"] },
    "{extra}",
    "{output}",
  ],
};

const QUALITY_WORDS = [
  [20, "Best"],
  [24, "Balanced"],
  [28, "Smaller"],
  [32, "Smallest"],
];

const DIAL_SWEEP_DEGREES = 270;
const PAGE_STEP = 3;
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

/* ---------- Command building ---------- */

const PLACEHOLDER = /\{([a-z0-9-]+)(?:\.(stem|name|dir))?\}/gi;

function fileParts(path) {
  const slash = path.lastIndexOf("/");
  const name = path.slice(slash + 1);
  const dot = name.lastIndexOf(".");
  return {
    name,
    stem: dot > 0 ? name.slice(0, dot) : name,
    dir: slash >= 0 ? path.slice(0, slash) : "",
  };
}

function isSet(field, value) {
  if (field.kind === "toggle") return value === true;
  return value !== undefined && value !== null && String(value) !== "";
}

function fill(template, values) {
  return template.replace(PLACEHOLDER, (_, id, part) => {
    const value = String(values[id] ?? "");
    return part ? fileParts(value)[part] : value;
  });
}

/** Builds argv from a task, following the manifest rules. Each item is { text, kind }. */
function buildArguments(task, values, extraWords) {
  const withOutput = { ...values, output: task.output ? fill(task.output.template, values) : "" };
  const out = [{ text: task.executable, kind: "exe" }];

  const walk = (items) => {
    for (const item of items) {
      if (typeof item !== "string") {
        const field = task.fields[item.if];
        if (isSet(field, values[item.if])) walk(item.then);
        else if (item.else) walk(item.else);
        continue;
      }
      if (item === "{extra}") {
        extraWords.forEach((word) => out.push({ text: word, kind: "extra" }));
        continue;
      }
      const whole = item.match(/^\{([a-z0-9-]+)(?:\.\w+)?\}$/i);
      const text = fill(item, withOutput);
      if (whole && text === "") continue; // an empty optional value produces no argument
      const fieldKind = whole ? (task.fields[whole[1]]?.kind ?? whole[1]) : null;
      const kind = item.startsWith("-") ? "flag"
        : (fieldKind === "inputFile" || fieldKind === "output") ? "path"
        : "val";
      out.push({ text, kind });
    }
  };
  walk(task.arguments);
  return out;
}

/** Shell-style quoting, for reading and copying only. Nothing here is ever executed. */
function displayQuote(text) {
  if (text !== "" && /^[A-Za-z0-9_\-+=.,:/@%^]+$/.test(text)) return text;
  return "'" + text.replace(/'/g, "'\\''") + "'";
}

/**
 * Splits the Extra arguments box into words the way MANIFEST_FORMAT describes:
 * whitespace separates words, "..." and '...' keep spaces, a backslash escapes the next character.
 */
function splitWords(input) {
  const words = [];
  let current = "";
  let inWord = false;
  let quote = null;
  for (let i = 0; i < input.length; i++) {
    const char = input[i];
    if (quote === "'") {
      if (char === "'") quote = null; else current += char;
      continue;
    }
    if (char === "\\" && i + 1 < input.length) {
      current += input[++i];
      inWord = true;
      continue;
    }
    if (quote === '"') {
      if (char === '"') quote = null; else current += char;
      continue;
    }
    if (char === "'" || char === '"') { quote = char; inWord = true; continue; }
    if (/\s/.test(char)) {
      if (inWord) { words.push(current); current = ""; inWord = false; }
      continue;
    }
    current += char;
    inWord = true;
  }
  if (quote) return { words: null, error: `Close the ${quote === '"' ? "double" : "single"} quote to finish the last word.` };
  if (inWord) words.push(current);
  return { words, error: null };
}

/** Renders argv into a code element, flashing the tokens that changed since the last render. */
function renderCommand(element, argv) {
  const previous = element._argv || [];
  element.textContent = "";
  argv.forEach((arg, index) => {
    if (index > 0) element.append(" ");
    const span = document.createElement("span");
    span.className = `tok t-${arg.kind}`;
    span.textContent = displayQuote(arg.text);
    if (previous.length && !previous.some((earlier) => earlier.text === arg.text)) span.classList.add("is-new");
    element.append(span);
  });
  element._argv = argv;
  element.dataset.copyText = argv.map((arg) => displayQuote(arg.text)).join(" ");
}

/* ---------- Links ---------- */

function applyLinks() {
  document.querySelectorAll("[data-link]").forEach((anchor) => {
    const url = LINKS[anchor.dataset.link];
    if (url) anchor.href = url;
  });
}

/* ---------- Demo: the dial and its controls ---------- */

function qualityWord(value) {
  return QUALITY_WORDS.find(([upTo]) => value <= upTo)[1];
}

function drawDialScale(svg, minimum, maximum) {
  const ns = "http://www.w3.org/2000/svg";
  const center = 160;
  const steps = maximum - minimum;
  for (let step = 0; step <= steps; step++) {
    const value = minimum + step;
    const angle = (-DIAL_SWEEP_DEGREES / 2 + (step / steps) * DIAL_SWEEP_DEGREES) * Math.PI / 180;
    const major = value === minimum || value === maximum || value === 25;
    const inner = major ? 124 : 128;
    const outer = 140;
    const line = document.createElementNS(ns, "line");
    line.setAttribute("x1", center + inner * Math.sin(angle));
    line.setAttribute("y1", center - inner * Math.cos(angle));
    line.setAttribute("x2", center + outer * Math.sin(angle));
    line.setAttribute("y2", center - outer * Math.cos(angle));
    line.setAttribute("class", major ? "tick is-major" : "tick");
    line.dataset.value = value;
    svg.append(line);
    if (major) {
      const label = document.createElementNS(ns, "text");
      label.setAttribute("x", center + 156 * Math.sin(angle));
      label.setAttribute("y", center - 156 * Math.cos(angle));
      label.textContent = value;
      svg.append(label);
    }
  }
}

function initDemo() {
  const dial = document.getElementById("dial");
  const command = document.getElementById("demo-cmd");
  if (!dial || !command) return;

  const quality = SHRINK_VIDEO.fields.quality;
  const scale = document.querySelector(".dial-scale");
  const readout = document.getElementById("dial-value");
  const word = document.getElementById("dial-word");
  const count = document.getElementById("demo-argc");
  const fileSelect = document.getElementById("demo-file");
  const mute = document.getElementById("demo-mute");
  const sizeInputs = document.querySelectorAll('input[name="size"]');

  drawDialScale(scale, quality.minimum, quality.maximum);
  const ticks = scale.querySelectorAll(".tick");

  const state = { input: fileSelect.value, size: SHRINK_VIDEO.fields.size.default, quality: quality.default, mute: false };

  const angleFor = (value) =>
    -DIAL_SWEEP_DEGREES / 2 + ((value - quality.minimum) / (quality.maximum - quality.minimum)) * DIAL_SWEEP_DEGREES;

  function update() {
    const argv = buildArguments(SHRINK_VIDEO, state, []);
    renderCommand(command, argv);
    count.textContent = `${argv.length} arguments`;
  }

  function setQuality(value) {
    const clamped = Math.min(quality.maximum, Math.max(quality.minimum, Math.round(value)));
    dial.style.setProperty("--angle", `${angleFor(clamped)}deg`);
    if (clamped === state.quality && readout.textContent === String(clamped)) return;
    state.quality = clamped;
    const label = qualityWord(clamped);
    readout.textContent = clamped;
    word.textContent = label;
    dial.setAttribute("aria-valuenow", clamped);
    dial.setAttribute("aria-valuetext", `${clamped}, ${label}`);
    ticks.forEach((tick) => tick.classList.toggle("is-on", Number(tick.dataset.value) <= clamped));
    update();
  }

  // Dragging turns the dial by the change in pointer angle around its centre, so it never jumps
  // across the gap at the bottom of the scale.
  let dragAngle = null;
  let dialAngle = 0;
  const pointerAngle = (event) => {
    const box = dial.getBoundingClientRect();
    const dx = event.clientX - (box.left + box.width / 2);
    const dy = event.clientY - (box.top + box.height / 2);
    return Math.atan2(dx, -dy) * 180 / Math.PI;
  };
  dial.addEventListener("pointerdown", (event) => {
    dial.setPointerCapture(event.pointerId);
    dragAngle = pointerAngle(event);
    dialAngle = angleFor(state.quality);
    dial.focus({ preventScroll: true, focusVisible: false });
    event.preventDefault();
  });
  dial.addEventListener("pointermove", (event) => {
    if (dragAngle === null) return;
    const now = pointerAngle(event);
    let delta = now - dragAngle;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    dragAngle = now;
    dialAngle = Math.min(DIAL_SWEEP_DEGREES / 2, Math.max(-DIAL_SWEEP_DEGREES / 2, dialAngle + delta));
    const span = quality.maximum - quality.minimum;
    setQuality(quality.minimum + ((dialAngle + DIAL_SWEEP_DEGREES / 2) / DIAL_SWEEP_DEGREES) * span);
  });
  const endDrag = () => { dragAngle = null; };
  dial.addEventListener("pointerup", endDrag);
  dial.addEventListener("pointercancel", endDrag);

  dial.addEventListener("keydown", (event) => {
    const steps = {
      ArrowUp: 1, ArrowRight: 1, ArrowDown: -1, ArrowLeft: -1, PageUp: PAGE_STEP, PageDown: -PAGE_STEP,
    };
    if (event.key in steps) setQuality(state.quality + steps[event.key]);
    else if (event.key === "Home") setQuality(quality.minimum);
    else if (event.key === "End") setQuality(quality.maximum);
    else return;
    event.preventDefault();
  });

  fileSelect.addEventListener("change", () => { state.input = fileSelect.value; update(); });
  mute.addEventListener("change", () => { state.mute = mute.checked; update(); });
  sizeInputs.forEach((input) => input.addEventListener("change", () => { state.size = input.value; update(); }));

  readout.textContent = "";
  setQuality(quality.default);
  command._argv = null; // the first render doesn't flash
  update();
}

/* ---------- Layers: Extra arguments and All options ---------- */

function initExtraArguments() {
  const input = document.getElementById("extra-input");
  const chips = document.getElementById("extra-chips");
  const status = document.getElementById("extra-status");
  const command = document.getElementById("extra-cmd");
  if (!input) return;
  const values = { input: "holiday.mov", size: "1280", quality: 23, mute: false };

  function update() {
    const { words, error } = splitWords(input.value);
    status.classList.toggle("is-error", Boolean(error));
    chips.classList.toggle("is-stale", Boolean(error));
    command.classList.toggle("is-stale", Boolean(error));
    if (error) {
      status.textContent = error;
      return;
    }
    const where = document.createElement("code");
    where.textContent = "{extra}";
    status.replaceChildren(`${words.length} ${words.length === 1 ? "word" : "words"}, added where the manifest says `, where, ".");
    chips.textContent = "";
    words.forEach((wordText) => {
      const chip = document.createElement("li");
      chip.textContent = wordText;
      chips.append(chip);
    });
    renderCommand(command, buildArguments(SHRINK_VIDEO, values, words));
  }
  input.addEventListener("input", update);
  document.querySelectorAll("[data-extra]").forEach((button) => {
    button.addEventListener("click", () => {
      input.value = button.dataset.extra;
      update();
    });
  });
  update();
  command._argv = null;
}

function initAllOptions() {
  const list = document.getElementById("opts");
  const filter = document.getElementById("opt-filter");
  const empty = document.getElementById("opts-empty");
  const command = document.getElementById("opts-cmd");
  if (!list) return;
  const rows = [...list.children];

  function update() {
    const argv = [{ text: "ffmpeg", kind: "exe" }, { text: "-i", kind: "flag" }, { text: "holiday.mov", kind: "path" }];
    list.querySelectorAll("input[data-opt]").forEach((toggle) => {
      if (!toggle.checked) return;
      argv.push({ text: toggle.dataset.opt, kind: "flag" });
      if (toggle.dataset.arg) argv.push({ text: toggle.dataset.arg, kind: "val" });
    });
    argv.push({ text: "holiday 2.mp4", kind: "path" });
    renderCommand(command, argv);
  }

  filter.addEventListener("input", () => {
    const query = filter.value.trim().toLowerCase();
    let shown = 0;
    rows.forEach((row) => {
      const match = row.textContent.toLowerCase().includes(query);
      row.hidden = !match;
      if (match) shown++;
    });
    empty.hidden = shown > 0;
  });
  list.addEventListener("change", update);
  update();
  command._argv = null;
}

/* ---------- Manifest: point at a line to light up what it draws ---------- */

function initManifestLinks() {
  const section = document.getElementById("manifests");
  if (!section) return;
  const light = (ref, on) =>
    section.querySelectorAll(`[data-ref="${ref}"]`).forEach((element) => element.classList.toggle("is-lit", on));
  section.querySelectorAll("[data-ref]").forEach((element) => {
    element.addEventListener("pointerenter", () => light(element.dataset.ref, true));
    element.addEventListener("pointerleave", () => light(element.dataset.ref, false));
  });
}

/* ---------- Copy buttons ---------- */

function initCopyButtons() {
  document.querySelectorAll("[data-copy]").forEach((button) => {
    const label = button.querySelector("span");
    const original = label.textContent;
    button.addEventListener("click", async () => {
      const source = document.querySelector(button.dataset.copy);
      const text = source.dataset.copyText || source.textContent;
      try {
        await navigator.clipboard.writeText(text);
        label.textContent = "Copied";
      } catch {
        // Clipboard access can be refused (for example on file:// in some browsers); select it instead.
        const range = document.createRange();
        range.selectNodeContents(source);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        label.textContent = "Selected, press ⌘C";
      }
      clearTimeout(button._reset);
      button._reset = setTimeout(() => { label.textContent = original; }, 1800);
    });
  });
}

applyLinks();
initDemo();
initExtraArguments();
initAllOptions();
initManifestLinks();
initCopyButtons();
