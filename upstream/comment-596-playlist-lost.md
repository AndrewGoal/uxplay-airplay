# Comment for #596 (HLS: playlist state lost mid-session)

Adding a data point from a macOS build, without a re-pair happening: the same
"playlist state is gone" failure shows up when the demuxer simply re-requests the
master playlist later in the same session.

Setup: UxPlay 1.74 master `48f5ce4`, macOS 13.7.8 Intel, GStreamer 1.28.9 framework,
iPhone X / iOS 16 (User-Agent `AirPlay/695.5.1`), YouTube iOS app, `-hls 2`.

Playback is fine for tens of minutes, then:

```
*** ERROR: requested master playlist /master.m3u8 not found
GStreamer error (video): source Not Found
GStreamer error (video): source Internal data stream error.
GStreamer error (video): typefindelement3 Stream doesn't contain enough data.
*** ERROR: airplay_video playlist  not found
```

after which the video pipeline is dead (with `playbin3` the same point shows
`hlsdemux2 Invalid manifest`). No client re-pairing appears in the log around it; the
sequence is the normal one (`/play`, `/rate`, occasional `scrub`), and `/play` had
happened minutes earlier with `Content-Location: mlhls://localhost/master.m3u8`.

So it is not only the re-pairing path: any later `GET /master.m3u8` from the demuxer
finds the store empty. If you want, I can run it with `-d 1` and attach the full log
plus the request sequence around the first 404 — the machine is available.

(Side note from the same setup, in case it helps others: `-hls 2` together with
`-custom "AVC:720;HEVC:0;VP9:0;AV1:0"` is what makes YouTube HLS usable on this Intel
iMac — without the filter the demuxer picks VP9/AV1 renditions that this machine can
only decode in software, and the pipeline stalls. `-custom` does work on master here,
so the callback registration in #616 is fine.)
