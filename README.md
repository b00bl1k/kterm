# kterm

Simple serial terminal for KolibriOS.

# Requirements

- [Fasm](https://flatassembler.net/) 1.7x
- [Tup](https://gittup.org/tup/) build system (optional)
- KolibriOS commit `#5593d344cd` or newer

# Build instructions

1. Clone the KolibriOS repository:

```sh
git clone https://git.kolibrios.org/KolibriOS/kolibrios.git
```

2. Clone this repository into kolibrios/programs/other/kterm:

```sh
cd kolibrios/programs/other
git clone https://git.kolibrios.org/b00bl1k/kterm.git
```

3. Build using either method:

With Tup (recommended):

    ```sh
    tup init
    tup
    ```

Or directly with FASM:

    ```sh
    fasm kterm.asm
    ```
