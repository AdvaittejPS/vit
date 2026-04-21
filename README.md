![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

Read the documentation for the project [here](./docs/info.md).

---

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real, physical chip. 

To learn more and get started, visit [tinytapeout.com](https://tinytapeout.com).

## Set up your Verilog project

1.  **Add your Verilog files** to the `src` folder.
2.  **Edit the `info.yaml`** and update the information about your project, paying special attention to the `source_files` and `top_module` properties. If you are upgrading an existing Tiny Tapeout project, check out the [online info.yaml migration tool](https://tinytapeout.com).
3.  **Edit `docs/info.md`** and add a comprehensive description of your project. 
4.  **Adapt the testbench** to your design. See `test/README.md` for more information. (Test your logic, or the silicon will test your patience).
5.  **GitHub Actions** will automatically build the ASIC files using LibreLane.
6.  **Enable GitHub Pages** in your repository settings to build the results page.

## Resources

* [FAQ](https://tinytapeout.com/faq)
* [Digital design lessons](https://tinytapeout.com/digital_design)
* [Learn how semiconductors work](https://tinytapeout.com/siliwiz)
* [Join the community](https://tinytapeout.com/discord)
* [Build your design locally](https://docs.tinytapeout.com/local-build)

## What next?

* Submit your design to the next shuttle.
* Edit this README and explain your design, how it works, and how to test it.
* Share your project on your social network of choice:
    * **LinkedIn:** #tinytapeout @TinyTapeout
    * **Mastodon:** #tinytapeout @matthewvenn
    * **X (Twitter):** #tinytapeout @tinytapeout
    * **Bluesky:** @tinytapeout.com
