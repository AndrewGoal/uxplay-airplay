# HLS: buffering messages from hlsdemux2 never reach 100%, pipeline stays PAUSED forever

## Environment

UxPlay 1.74 (master `48f5ce4`), macOS 13.7.8 Intel, GStreamer 1.28.9 (official macOS
framework), YouTube iOS app → in-app AirPlay icon (`-hls`).

## Symptom

With `-hls` (playbin3 / hlsdemux2) the video plays for a few seconds and then freezes
permanently. Nothing is logged at default verbosity: no ERROR, no WARNING. The client
keeps sending `on_video_rate = 1.0 / 0.0` alternately.

## Cause

`video_renderer.c`, `GST_MESSAGE_BUFFERING`:

```c
if (percent < 100) {
    gst_element_set_state (renderer->pipeline, GST_STATE_PAUSED);
} else {
    hls_buffer_full = TRUE;
    gst_element_set_state (renderer->pipeline, GST_STATE_PLAYING);
}
```

hlsdemux2 reports buffering continuously during playback in `stream` mode and does not
reach 100% on this setup, so the pipeline is paused on a 3x% message and never resumed.

Reproduced without a phone, on a public HLS stream:

```
gst-launch-1.0 -m playbin3 uri=https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8 \
    video-sink=fakesink audio-sink=fakesink
```

30 s of playback → **367** `GstMessageBuffering` messages from `hlsdemux2-0`,
`buffer-percent` going 36 → 37 → 38 → 39 with `buffering-mode=stream`,
`avg-in-rate=-1`, `buffering-left=-1`.

## Local workaround that works

Only honour buffering while the pipeline has not started playing yet:

```c
if (percent < 100) {
    if (!hls_playing) {   /* hls_playing is set on the PAUSED->PLAYING transition */
        gst_element_set_state (renderer->pipeline, GST_STATE_PAUSED);
    }
} else {
    ...
}
```

After that the same stream played for tens of minutes (with `-hls 2` and
`-custom "AVC:720;HEVC:0;VP9:0;AV1:0"`, i.e. H.264 only).

Note the first-buffering case still needs the pause, so a plain "ignore all buffering"
patch would regress start-up on slow links.
