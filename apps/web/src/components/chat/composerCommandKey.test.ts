import { DraftId } from "../../composerDraftStore";
import { describe, expect, it, vi } from "vite-plus/test";

import { composerCommandKeyHandler } from "./composerCommandKey";

function setup(options: { readonly prompt?: string; readonly menuOpen?: boolean } = {}) {
  const dismiss = vi.fn();
  const submit = vi.fn();
  const saveDraft = vi.fn();
  const promptRef = { current: options.prompt ?? "" };
  const handler = composerCommandKeyHandler({
    keybindings: [],
    sendShortcut: "enter",
    routeKind: "draft",
    phase: "ready",
    isCompacting: false,
    followUpBehavior: "queue",
    isSoftwareKeyboardOpen: false,
    planModeUiEnabled: false,
    isLiteralPendingAnswer: false,
    pendingUserInputs: [],
    promptHistoryEntries: [],
    promptHistoryPositionRef: { current: null },
    composerDraftTarget: DraftId.make("draft"),
    promptRef,
    composerImagesRef: { current: [] },
    composerFilesRef: { current: [] },
    composerTerminalContextsRef: { current: [] },
    composerPreviewAnnotations: [],
    composerReviewComments: [],
    promptSuggestion: { text: "Run tests", dismiss },
    composerEditorRef: { current: null },
    composerMenuOpenRef: { current: options.menuOpen ?? false },
    composerMenuItemsRef: { current: [] },
    activeComposerMenuItemRef: { current: null },
    setComposerDraftPrompt: saveDraft,
    setComposerCursor: vi.fn(),
    setComposerTrigger: vi.fn(),
    setComposerHighlightedItemId: vi.fn(),
    dismissComposerTrigger: vi.fn(),
    toggleInteractionMode: vi.fn(),
    nudgeComposerMenuHighlight: vi.fn(),
    onSelectComposerItem: vi.fn(),
    resolveActiveComposerTrigger: () => ({ trigger: null }),
    readComposerSnapshot: () => ({ value: "" }),
    applyPromptReplacement: () => false,
    submitComposer: submit,
  });
  return { handler, dismiss, submit, saveDraft, promptRef };
}

describe("next prompt keyboard acceptance", () => {
  it.each(["Tab", "ArrowRight"])("accepts and consumes on %s without sending", (key) => {
    const { handler, dismiss, submit, saveDraft, promptRef } = setup();
    expect(
      handler(key, {
        key,
        shiftKey: false,
        altKey: false,
        metaKey: false,
        ctrlKey: false,
        isComposing: false,
      } as KeyboardEvent),
    ).toBe(true);
    expect(promptRef.current).toBe("Run tests");
    expect(saveDraft).toHaveBeenCalledWith(DraftId.make("draft"), "Run tests");
    expect(dismiss).toHaveBeenCalledOnce();
    expect(submit).not.toHaveBeenCalled();
  });

  it("dismisses on Escape without changing or sending the draft", () => {
    const { handler, dismiss, submit, saveDraft } = setup();
    expect(
      handler("Escape", {
        key: "Escape",
        shiftKey: false,
        altKey: false,
        metaKey: false,
        ctrlKey: false,
        isComposing: false,
      } as KeyboardEvent),
    ).toBe(true);
    expect(dismiss).toHaveBeenCalledOnce();
    expect(saveDraft).not.toHaveBeenCalled();
    expect(submit).not.toHaveBeenCalled();
  });
});

describe("next prompt keyboard guards", () => {
  const event = (key: string, overrides: Partial<KeyboardEvent> = {}) =>
    ({
      key,
      shiftKey: false,
      altKey: false,
      metaKey: false,
      ctrlKey: false,
      isComposing: false,
      ...overrides,
    }) as KeyboardEvent;

  const expectUntouched = ({ dismiss, saveDraft, submit }: ReturnType<typeof setup>) => {
    expect(dismiss).not.toHaveBeenCalled();
    expect(saveDraft).not.toHaveBeenCalledWith(DraftId.make("draft"), "Run tests");
    expect(submit).not.toHaveBeenCalled();
  };

  it.each(["Tab", "ArrowRight", "Escape"])("leaves %s to an open composer menu", (key) => {
    const context = setup({ menuOpen: true });
    context.handler(key, event(key));
    expectUntouched(context);
    expect(context.promptRef.current).toBe("");
  });

  it.each(["Tab", "ArrowRight", "Escape"])("ignores %s once the user has typed", (key) => {
    const context = setup({ prompt: "my own words" });
    context.handler(key, event(key));
    expectUntouched(context);
    expect(context.promptRef.current).toBe("my own words");
  });

  it.each([
    ["shiftKey", "Tab"],
    ["altKey", "ArrowRight"],
    ["metaKey", "ArrowRight"],
    ["ctrlKey", "Tab"],
  ] as const)("ignores %s+%s", (modifier, key) => {
    const context = setup();
    context.handler(key, event(key, { [modifier]: true }));
    expectUntouched(context);
    expect(context.promptRef.current).toBe("");
  });

  it.each(["Tab", "ArrowRight", "Escape"])("ignores %s during IME composition", (key) => {
    const context = setup();
    context.handler(key, event(key, { isComposing: true }));
    expectUntouched(context);
    expect(context.promptRef.current).toBe("");
  });
});
