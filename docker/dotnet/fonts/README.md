# Fonts

Reports and charts are laid out with Arial, Times New Roman and Verdana.
These are Microsoft fonts and are not part of this repository; the image
build installs them in one of two ways.

## Automatic: Core fonts for the Web (default)

When this directory holds no `.ttf` files, building the image downloads
Microsoft's "Core fonts for the Web" in their original self-extracting
cabinets (`arial32.exe`, `times32.exe`, `verdan32.exe`, listed with their
sha256 in `../deps.txt`) and extracts the twelve `.ttf` files into the image.
These are the same files Debian and Ubuntu install with
`ttf-mscorefonts-installer`.

The fonts are used under Microsoft's EULA, which permits free use but not
distribution as part of another product; building the image means accepting
it: <https://corefonts.sourceforge.net/eula.htm>.

The build needs to reach SourceForge (behind a proxy, configure Docker's:
<https://docs.docker.com/engine/cli/proxy/>). Without it, place the three
cabinets in `docker/dotnet/`.

## From Windows (identical output)

The Core fonts date from 1998 to 2000. Current Windows versions of the same
faces have slightly different metrics, so a report can wrap or break a page
in a different place than on a Windows server. For output identical to
Windows, copy these files here from a licensed Windows installation
(`C:\Windows\Fonts`) before building:

    arial.ttf  arialbd.ttf  arialbi.ttf  ariali.ttf
    times.ttf  timesbd.ttf  timesbi.ttf  timesi.ttf
    verdana.ttf  verdanab.ttf  verdanai.ttf  verdanaz.ttf

Any `.ttf` here replaces the download completely, so copy the whole set.

## Changing fonts later

The image is built once. After adding or removing files here, rebuild it:

    docker compose build esystem && docker compose up -d
