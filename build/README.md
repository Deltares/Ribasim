# Create Binaries

Build the app with:

```sh
pixi run build-ribasim-cli
```

Build the shared library with:

```sh
pixi run build-libribasim
```

Build both with:

```sh
pixi run build
```

> :warning: If the build is failing, because it cannot find certain files, chances are high that you need to enable long paths in Windows.
