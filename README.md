
# PC/GEOS

This repository is the official place to hold all the source codes around the PC/GEOS graphical user interface and its sophisticated applications. It is the source to build SDK and release versions of PC/GEOS. It is the place to collaborate on further developments.

The base of this repository is the source code used to build Breadbox Ensemble 4.13, reduced by some modules identified as critical regarding the license chosen for the repository.

While now WATCOM is used to compile the C parts, the full SDK is available for Windows and Linux.

---

## How to build?

### Prerequisites

The SDK requires "sed" (https://en.wikipedia.org/wiki/Sed) and "perl" (https://en.wikipedia.org/wiki/Perl) to be installed. 

- **Linux:** Both tools are pre-installed in most Linux distributions. Additionally, if you want to use `swat` for debugging with good system integration, install the `xdotools` package. This ensures `swat` receives keyboard focus when needed.
- **Windows:** Install "sed" by adding the `usr/bin` of the official Git distribution (https://git-scm.com) to the path (or use Cygwin). For Perl, use the "Strawberry Perl" distribution (http://strawberryperl.com).

---

### Install WATCOM and set environment

#### Linux Instructions:
1. Download and extract the latest Open Watcom snapshot:
   ```bash
   wget https://github.com/open-watcom/open-watcom-v2/releases/download/2020-12-01-Build/ow-snapshot.tar.gz
   tar -xzf ow-snapshot.tar.gz -C /opt
   ```

2. Set environment variables:
   ```bash
   export WATCOM=/opt/open-watcom-v2
   export ROOT_DIR=$HOME/Geos/pcgeos
   export LOCAL_ROOT=$ROOT_DIR/Local
   export BASEBOX=basebox
   export PATH=$WATCOM/binl:$ROOT_DIR/bin:$PATH
   ```

3. Install `xdotool` (if not already installed):
   ```bash
   sudo apt-get install xdotool
   ```

#### Windows Instructions:
1. Download and extract the latest Open Watcom snapshot from [Open Watcom Releases](https://github.com/open-watcom/open-watcom-v2/releases/download/2020-12-01-Build/ow-snapshot.tar.gz) to `C:\WATCOM-V2`.

2. Set environment variables:
   ```cmd
   set WATCOM=C:\WATCOM-V2
   set ROOT_DIR=C:\Geos\pcgeos
   set LOCAL_ROOT=C:\Geos\pcgeos\Local
   set BASEBOX=basebox
   PATH %WATCOM%\binnt;%ROOT_DIR%\bin;C:\Geos\pcgeos-basebox\binnt;%PATH%;C:\Program Files\Git\usr\bin
   ```

---

### Building PC/GEOS SDK

#### Linux Instructions:
1. Build the `pmake` tool:
   ```bash
   cd $ROOT_DIR/Tools/pmake/pmake
   wmake install
   ```

2. Build all other SDK tools:
   ```bash
   cd $ROOT_DIR/Installed/Tools
   pmake install
   ```

3. Build all PC/GEOS (target) components:
   ```bash
   cd $ROOT_DIR/Installed
   pmake
   ```

4. Build the target environment:
   ```bash
   cd $ROOT_DIR/Tools/build/product/bbxensem/Scripts
   perl -I. buildbbx.pl
   ```
   - Answer the questions as follows:
     - Platform: `nt`
     - EC version: `y`
     - DBCS: `n`
     - Geodes: `y`
     - VM files: `n`
     - Path to `gbuild` folder: `<path to your LOCAL_ROOT folder>`

#### Windows Instructions:
1. Build the `pmake` tool:
   ```cmd
   cd %ROOT_DIR%\Tools\pmake\pmake
   wmake install
   ```

2. Build all other SDK tools:
   ```cmd
   cd %ROOT_DIR%\Installed\Tools
   pmake install
   ```

3. Build all PC/GEOS (target) components:
   ```cmd
   cd %ROOT_DIR%\Installed
   pmake
   ```

4. Build the target environment:
   ```cmd
   cd %ROOT_DIR%\Tools\build\product\bbxensem\Scripts
   perl -I. buildbbx.pl
   ```
   - Answer the questions as follows:
     - Platform: `nt`
     - EC version: `y`
     - DBCS: `n`
     - Geodes: `y`
     - VM files: `n`
     - Path to `gbuild` folder: `<path to your LOCAL_ROOT folder>`

---

### Launch the Target Environment

#### Linux Instructions:
1. Ensure DOSBox or `pcgeos-basebox` is installed:
   ```bash
   sudo apt-get install dosbox
   ```
   Or install [pcgeos-basebox](https://github.com/bluewaysw/pcgeos-basebox/tags).

2. Launch the target environment:
   ```bash
   $ROOT_DIR/bin/target
   ```
   - The "swat" debugger will stop after the first boot stage.
   - At the `=>` prompt, enter:
     - `quit`: to detach the debugger and launch PC/GEOS stand-alone.
     - `c`: to continue with the debugger running in the background (slower).

#### Windows Instructions:
1. Ensure DOSBox is installed and added to your PATH, or use the `BASEBOX` environment variable pointing to `pcgeos-basebox`.

2. Launch the target environment:
   ```cmd
   %ROOT_DIR%\bin\target
   ```
   - Follow the same steps as Linux for the debugger.

---

### Customize Target Environment

To customize settings for your environment, avoid editing the base configuration file:
- **Linux:** `$ROOT_DIR/bin/basebox.conf`
- **Windows:** `%ROOT_DIR%\bin\basebox.conf`

Instead, create a `basebox_user.conf` file in your local root folder:
- **Linux:** `$LOCAL_ROOT/basebox_user.conf`
- **Windows:** `%LOCAL_ROOT%\basebox_user.conf`

Example content:
```ini
[cpu]
cycles=55000
```

---

## How to develop?

PC/GEOS comes with extensive technical documentation that describes tools, programming languages, and API calls from the perspective of an SDK user. This documentation can be found in the `TechDocs` folder and is available in Markdown format.

You can find a browseable, searchable version of the documentation here: https://bluewaysw.github.io/pcgeos/

---

For efficient collaboration, join our developer community on Discord: [Blueway Softworks Discord](https://discord.gg/qtMqgZXhf9).

