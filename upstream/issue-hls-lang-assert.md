# -hls aborts with an assertion when no locale environment variable is set

## Environment

UxPlay 1.74 (master `48f5ce4`), macOS 13.7.8, GStreamer 1.28.9 framework.
Reproduced from a non-interactive shell / launchd-style environment, where
`LANGUAGE`, `LC_ALL`, `LC_MESSAGES` and `LANG` are all unset.

## Symptom

```
$ env -u LANG -u LC_ALL -u LANGUAGE -u LC_MESSAGES uxplay -n iMac -hls
Bail out! ERROR:~/UxPlay/uxplay.cpp:3478:void real_main(int, char **):
    assertion failed: (!lang_system.empty())
Abort trap: 6
```

Without `-hls` the same command starts normally. It also works in an interactive
Terminal, because the shell exports `LANG`.

## Cause

`real_main()` collects the system language preference from `LANGUAGE`, `LC_ALL`,
`LC_MESSAGES`, `LANG` (in that order) and then asserts it is non-empty:

```c
        g_assert(!lang_system.empty());
```

Any environment without a locale (cron, launchd agent, some IDEs, `env -i`,
containers) aborts instead of just having no preference.

## Suggested fix

Treat "no locale" as "no preference" and let the rest of the HLS path work
(`-lang` can still be given explicitly), e.g.

```c
        if (!lang_system.empty()) {
            ...existing normalisation...
        } else {
            lang_system = "en";   /* or leave empty and skip language selection */
        }
```

A minimal repro (`env -u LANG -u LC_ALL -u LANGUAGE -u LC_MESSAGES uxplay -hls`)
and a one-line guard would be enough to keep this from looking like a crash.
