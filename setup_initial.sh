#!/bin/bash

echo "add remote QCS Repo"
git remote add qcs_repo git@github.com:gururajah-nd/git_clone_testing.git

echo "fetch required branch"
git fetch qcs_repo qcs_1.3

echo "checkout requires qcs file"
git checkout qcs_repo/qcs_1.3 setup-environment layers/meta-virtualization/

echo "remove unecessary qcs files from git index"
git rm --cached -r layers/meta-virtualization/ setup-environment

