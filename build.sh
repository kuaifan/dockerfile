#!/bin/bash

# 遍历当前目录
for dir in `ls`
do
    # 判断是否目录
    if [ -d $dir ]
    then
        dockerFile=$dir"/Dockerfile"
        configFile=$dir"/config.ini"
        # 判断是否存在Dockerfile
        if [ -f $dockerFile ]
        then
            imageName="kuaifan/"$dir
            imageTag="latest"
            # 判断是否存在config文件
            if [ -f $configFile ]
            then
                # 读取config文件
                while read line
                do
                    # 判断是否是镜像名称
                    if [[ $line =~ "imageName" ]]
                    then
                        imageName=${line#*=}
                        continue
                    fi
                    # 判断是否是镜像标签
                    if [[ $line =~ "imageTag" ]]
                    then
                        imageTag=${line#*=}
                        continue
                    fi
                done < $configFile
            fi
            echo "-------------------"
            echo $imageName":"$imageTag
            response=$(curl -s -o /dev/null -w "%{http_code}" -X GET -u $DOCKERHUB_USERNAME:$DOCKERHUB_TOKEN "https://hub.docker.com/v2/repositories/$imageName/tags/$imageTag")
            if [ $response == 200 ]
            then
                echo "Already exists"
            else
                pushd $dir > /dev/null
                echo "Start building..."
                docker buildx build --platform linux/amd64,linux/arm64 --tag $imageName":"$imageTag . --push
                echo "Build completed"
                popd > /dev/null
            fi
        fi
    fi
done