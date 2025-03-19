#!/bin/bash

git remote add qcs_repo git@github.com:gururajah-nd/git_clone_testing.git
git fetch qcs_repo qcs_1.3

git checkout qcs_repo/qcs_1.3 setup-environment layers/meta-virtualization/
git rm --cached -r layers/meta-virtualization/ setup-environment

