## villein: tiny script for performance measuring

open 2 shells and run:

```
$ ruby perf.rb
```

```
$ serf agent &
$ serf join localhost:17946
```

then:

```
$ ruby perf2.rb
```
