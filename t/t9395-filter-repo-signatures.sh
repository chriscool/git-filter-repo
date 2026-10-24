#!/bin/bash

test_description='Commit and tag signature tests for filter-repo'

. ./test-lib.sh
. "$TEST_DIRECTORY/lib-gpg.sh"

export PATH=$(dirname $TEST_DIRECTORY):$PATH  # Put git-filter-repo in PATH

if ! test_have_prereq GPGSSH
then
	skip_all='skipping signature tests as ssh signing is not available'
	test_done
fi

compare_revs () {
	local op="$1" &&
	local other="$2" &&
	local rev ours theirs &&

	case "$op" in
	=|!=) ;;
	*) BUG "compare_revs: operator must be '=' or '!=', not '$op'" ;;
	esac &&

	shift 2 &&
	for rev in "$@"
	do
		ours=$(git rev-parse --verify "$rev") &&
		theirs=$(git -C "$other" rev-parse --verify "$rev") ||
		return 1

		if ! test "$ours" "$op" "$theirs"
		then
			echo >&4 "error: compare_revs: '$rev': $ours $op $theirs (in $other) is false"
			return 1
		fi
	done
}

test_expect_success 'setup signed history for signature tests' '
	test_create_repo signed &&
	(
		cd signed &&
		git config gpg.format ssh &&
		git config user.signingkey "${GPGSSH_KEY_PRIMARY}" &&
		git config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&
		git config commit.gpgSign true &&

		test_commit initial &&
		git branch side &&
		test_commit second &&
		git checkout side &&
		test_commit third &&
		git checkout - &&
		test_merge merge side &&
		git tag -s -m "signed tag" v1.0 &&

		git verify-commit initial second third merge &&
		git verify-tag v1.0
	)
'

test_expect_success 'signatures are stripped by default' '
	git clone --no-local signed stripped &&
	(
		cd stripped &&
		git config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&

		git filter-repo --force &&

		compare_revs != ../signed initial second third merge v1.0 &&

		git rev-list --all | git cat-file --batch >commits &&
		! grep -E "^gpgsig(-sha256)? " commits &&
		test_must_fail git verify-commit HEAD &&

		git cat-file tag v1.0 >tag &&
		! grep "BEGIN SSH SIGNATURE" tag &&
		test_must_fail git verify-tag v1.0
	)
'

test_done
