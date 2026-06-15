# Word list sources

Raw inputs for `Tools/GenerateLexicons.swift` (`make lexicons`). The raw files
are large and gitignored — only the compiled `Resources/Lexicons/*.clex|*.cngm`
binaries are committed. Re-download with the commands below.

## Unigrams — hermitdave/FrequencyWords (CC-BY-SA 4.0)

OpenSubtitles-2018-derived frequency lists, one `word count` per line:

```sh
cd Tools/wordlists
for lang in en fr es de it pt ru; do
  curl -sfLO "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/${lang}/${lang}_50k.txt"
done
```

License: CC-BY-SA 4.0 — attribution shipped in the app's about screen.
https://github.com/hermitdave/FrequencyWords

## Word bigrams — Tatoeba sentence exports (CC-BY 2.0 FR)

Per-language sentence TSVs (`id\tlang\tsentence`); bigram counts are derived
by the generator. Used for every language, English included. (Norvig's
`count_2w.txt` was dropped: its Google trillion-word origin carries no clear
commercial-redistribution grant.) Leipzig Corpora was rejected (non-commercial
license).

```sh
for pair in "en eng" "fr fra" "es spa" "de deu" "it ita" "pt por" "ru rus"; do
  short=${pair%% *}; iso=${pair##* }
  curl -sfL --retry 3 -o ${short}_sentences.tsv.bz2 \
    "https://downloads.tatoeba.org/exports/per_language/${iso}/${iso}_sentences.tsv.bz2"
done
bunzip2 -kf *_sentences.tsv.bz2
```

License: CC-BY 2.0 FR — attribution shipped in the app's about screen.
https://tatoeba.org/en/downloads
