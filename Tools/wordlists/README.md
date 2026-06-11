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

## English word bigrams — Norvig / Google trillion-word corpus

`w1 w2\tcount` per line, free to use (https://norvig.com/ngrams/):

```sh
curl -sfLO "https://norvig.com/ngrams/count_2w.txt"
```

## Non-English word bigrams — Tatoeba sentence exports (CC-BY 2.0 FR)

Per-language sentence TSVs (`id\tlang\tsentence`); bigram counts are derived
by the generator. Leipzig Corpora was rejected (non-commercial license).

```sh
for pair in "fr fra" "es spa" "de deu" "it ita" "pt por" "ru rus"; do
  short=${pair%% *}; iso=${pair##* }
  curl -sfL --retry 3 -o ${short}_sentences.tsv.bz2 \
    "https://downloads.tatoeba.org/exports/per_language/${iso}/${iso}_sentences.tsv.bz2"
done
bunzip2 -kf *_sentences.tsv.bz2
```

License: CC-BY 2.0 FR — attribution shipped in the app's about screen.
https://tatoeba.org/en/downloads
