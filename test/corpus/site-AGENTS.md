# Agents

1. Read REQUIREMENTS.md. Keep the site to what it says. Prefer deleting to adding.
2. Edit pages in `public/` by hand. No generator, no framework, no build step. The beam page and the
   wallpaper module (`scripts/build-wallpaper.sh`) are the exceptions.
3. Never edit `public/play/beamdiag/index.html`. Change the beam in `beamdiag/`, then run
   `scripts/build-beam.sh` and commit the page with the source.
4. Never change or remove a URL in `fixed-urls.txt`: the App Store links to them.
5. Commit to `main`. Turn on the VPN, then run `scripts/deploy.sh`. It runs the check, deploys and
   tests the URLs.
