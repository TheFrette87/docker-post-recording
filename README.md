# docker-post-recording

Watches for .ts files made by Emby Live TV recordings, converts them to a friendly format, extracts .srt file, add chapters with comchap or remove them with comcut.
Forked from https://github.com/chacawaca/docker-post-recording to modify for my own needs as I am using the TrueNAS Application for Emby and could not follow along perfectly with the work of https://github.com/BillOatmanWork/Emby.ComSkipper.

Running TrueNAS OS Version:25.04.2.6 on a Dell r730xd with a NVidia Quadro P2200 passing through to Emby as well as this plugin for remuxing.

## Docker Compose (YAML)

```shell
version: "3.9"

services:
  post-recording:
    container_name: post-recording
    image: chacawaca/post-recording
    restart: always
    environment:
      PUID: 1000
      PGID: 1000
      SOURCE_EXT: ts
      CONVERSION_FORMAT: mkv
      # SUBTITLES: 0 = Yes, 1 = No
      SUBTITLES: 0
      # DELETE_TS: 0 = Yes, 1 = No
      DELETE_TS: 1
      # POST_PROCESS options: comchap or comcut
      POST_PROCESS: comchap
    volumes:
      - /mnt/Tank/docker/data/comskipper:/config:rw
      - /mnt/Tank/Media/Recorded TV:/watch:rw
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

Where:

- `/config`: This is where the application stores its configuration, log and any files needing persistency. 
- `/watch`: This location contains .ts files that need converting. Other files are not processed.  
- `/backup`: Optional, only used if DELETE_TS is set to 2.
- `DELETE_TS`: After converting remove the original .ts recording file. 0 = Yes, 1 = No, 2 = Move to backup directory **USE DELETE_TS=1 UNTIL YOU'RE SURE IT WORKS WITH YOUR VIDEO RECORDINGS.**
- `SUBTITLES`: Extract subtitles to .srt. 0= Yes, 1 = No
- `CONVERSION_FORMAT`: Select output extension, your custom.sh need to be valid for this extension.
- `SOURCE_EXT`: If you want to convert something else than .ts
- `POST_PROCESS`: option are comchap or comcut. default: comchap
- `PUID`: ID of the user the application runs as.
- `PGID`: ID of the group the application runs as.

## Configuration: 

- /scripts/custom.sh **need to be configured** by you, some examples are there to help you configure this for your need. **(The custom-nvidia-cpu.sh.example file provided in the examples folder uses the available NVidia GPU first, and will revert to CPU encoding if necessary. It also scales the video to 720p for anything at a resolution higher, and remuxes audio to 192k. You will have to overwrite custom.sh with this file if desired.)**
- /hooks can be configured to execute custom code
- /comskip/comskip.ini can be configured too. The file I've included seems to do a decent job as-is for my recordings.
- If you are using the 'comchap' Post Processing Feature, Move comskipper.dll from www.github.com/BillOatmanWork/Emby.ComSkipper/releases zip file into /EmbyConfig/plugins Directory and reboot your Emby server. (I used a Host Path in TrueNAS when configuring Emby here, so I could drop easily from a SMB share)

## Nvidia GPU Use  
- Using the TrueNAS Nvidia drivers provided with TrueNAS OS Version:25.04.2.6 (Driver Version: 550.142)
- To enable NVIDIA drivers in TrueNAS Scale, go to Apps > Configuration > Settings and check the option to install NVIDIA drivers. 
- Include the following into your YAML if you've not already done so:
```shell
deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

## Projects used

www.github.com/chacawaca/docker-post-recording

www.github.com/BillOatmanWork/Emby.ComSkipper

www.github.com/djaydev/docker-recordings-transcoder  

www.github.com/BrettSheleski/comchap  

www.github.com/erikkaashoek/Comskip  

www.github.com/jlesage/docker-handbrake  

www.github.com/ffmpeg/ffmpeg  

www.github.com/CCExtractor/ccextractor  

www.github.com/jrottenberg/ffmpeg
