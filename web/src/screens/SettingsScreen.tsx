import { Icon, type IconName } from '../components/Icon';
import { useAppearance } from '../hooks/useAppearance';
import { MODES, PALETTES, type ModePreference } from '../theme';

/**
 * Everything about this device rather than about the diary.
 *
 * Which is, for now, only appearance — and that is the point of giving it its own screen rather
 * than a control in the nav. A paper is chosen once and then lived with; putting a palette switch
 * in the chrome would ask about it on every visit, which is the opposite of what a diary should
 * feel like. Nothing here is sent anywhere: the choice lives in this browser and this browser only.
 */
export function SettingsScreen() {
  const { appearance, resolved, setPalette, setMode } = useAppearance();

  return (
    <section className="stack stack--loose">
      <header className="page-header">
        <div className="page-header__titles">
          <span className="page-header__eyebrow">This browser</span>
          <h1>Settings</h1>
        </div>
      </header>

      <div className="card stack">
        <div className="stack stack--tight">
          <h2 className="settings__heading">Appearance</h2>
          <p className="muted">
            Three papers to write on, each with a light and a dark half. The choice is kept in this
            browser and is never sent to the diary.
          </p>
        </div>

        <fieldset className="settings__group">
          <legend className="eyebrow">Light or dark</legend>
          <div className="segmented" role="group">
            {MODES.map((mode) => (
              <button
                key={mode.id}
                type="button"
                className="segmented__option"
                aria-pressed={appearance.mode === mode.id}
                onClick={() => setMode(mode.id)}
              >
                <Icon name={MODE_ICONS[mode.id]} />
                {mode.label}
              </button>
            ))}
          </div>
          {/*
            "System" is the default and the only option whose result is not written on its own
            label, so it says what it currently works out to. The other two already have.
          */}
          {appearance.mode === 'system' && (
            <p className="field-hint">
              Following this device, which is currently set to {resolved}.
            </p>
          )}
        </fieldset>

        <fieldset className="settings__group">
          <legend className="eyebrow">Paper</legend>
          {/*
            Radios rather than buttons: this is one choice out of three, and a radio group is what
            arrow keys, screen readers and the browser's own form semantics already understand.
            The visible control is the whole card; the input itself is hidden but real.
          */}
          <div className="palette-grid">
            {PALETTES.map((palette) => (
              <label
                key={palette.id}
                className={`palette-option${appearance.palette === palette.id ? ' palette-option--selected' : ''}`}
              >
                <input
                  type="radio"
                  name="palette"
                  value={palette.id}
                  className="visually-hidden"
                  checked={appearance.palette === palette.id}
                  onChange={() => setPalette(palette.id)}
                />
                {/*
                  The preview is not a picture of the palette — it is the palette. The same
                  `data-palette`/`data-mode` attributes the whole app is themed by also work on a
                  div, so these swatches read the real tokens and can never drift from them.
                */}
                <span
                  className="palette-preview"
                  data-palette={palette.id}
                  data-mode={resolved}
                  aria-hidden="true"
                >
                  <span className="palette-preview__card">
                    <span className="palette-preview__title" />
                    <span className="palette-preview__line" />
                    <span className="palette-preview__line palette-preview__line--short" />
                  </span>
                  <span className="palette-preview__dots">
                    {FEELING_GROUPS.map((group) => (
                      <span
                        key={group}
                        className="palette-preview__dot"
                        style={{ background: `var(--feeling-group-${group})` }}
                      />
                    ))}
                  </span>
                </span>
                <span className="palette-option__body">
                  <span className="palette-option__name">
                    {palette.label}
                    {/* Selection is marked by the border, the fill *and* this tick, so it
                        survives greyscale — the same rule the feeling chips follow. */}
                    {appearance.palette === palette.id && (
                      <span className="palette-option__check">
                        <Icon name="check" />
                      </span>
                    )}
                  </span>
                  <span className="palette-option__description">{palette.description}</span>
                </span>
              </label>
            ))}
          </div>
        </fieldset>
      </div>
    </section>
  );
}

const MODE_ICONS: Record<ModePreference, IconName> = {
  system: 'monitor',
  light: 'sun',
  dark: 'moon',
};

/** The four groups, in valence order, so the preview's dots read the same way the calendar's do. */
const FEELING_GROUPS = ['uplifted', 'steady', 'tense', 'low'] as const;
