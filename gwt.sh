#!/usr/bin/env zsh

# Function to display an error message and exit.
# Usage: die "Error message"
function die() {
    echo "Error: $1" >&2
    return 1
}

# Function to display the script's help message.
function usage() {
    cat <<EOF
gwt - A tool to help with git worktree basic commands.

USAGE:
    gwt [COMMAND]

COMMANDS:
    add <dir-name> <branch-name>
        Creates a new worktree. If the branch does not exist, it will be created from the current HEAD.
        The worktree will be created in <git-root>/.worktrees/<dir-name>.

    remove
        Lists existing worktrees and removes the selected one.

    setup
        Configures git to globally ignore the '.worktrees' directory.

    help, --help, -h
        Shows this help message.

If no command is provided, the script will list existing worktrees
to allow for quick switching between them.
EOF
}

# Checks if the required commands (git, fzf) are installed.
function check_dependencies() {
    if ! command -v git &>/dev/null; then
        die "Git is not installed. Please install Git to continue."
    fi
    if ! command -v fzf &>/dev/null; then
        die "fzf is not installed. Please install fzf to continue."
    fi
}

# Checks if the current directory is inside a Git repository.
function check_in_git_repo() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        die "Not inside a Git repository."
    fi
}

# Configures the global gitignore to ignore the .worktrees directory.
function setup_gitignore() {
    local global_gitignore
    global_gitignore=$(git config --global core.excludesfile)

    if [[ ${global_gitignore:0:2} == "~/" ]]; then
        global_gitignore=$HOME/${global_gitignore:2}
    fi

    if [[ -z "$global_gitignore" ]]; then
        echo "Global gitignore not found."
        # If there is no global gitignore, create one at ~/.gitignore_global
        global_gitignore="$HOME/.gitignore_global"
        echo "Creating global gitignore at: $global_gitignore"
        git config --global core.excludesfile "$global_gitignore"
    fi

    # Add .worktrees to the global gitignore if it's not already there
    if ! grep -q "^\.worktrees$" "$global_gitignore"; then
        echo "'.worktrees' not found in gitignore."
        echo "Adding '.worktrees' to global gitignore: $global_gitignore"
        echo ".worktrees" >> "$global_gitignore"
    else
        echo "The '.worktrees' directory is already in the global gitignore."
    fi
}

# Uses fzf to select a worktree from the list.
# Returns the selected line from the 'git worktree list' command.
function get_worktree() {
    git worktree list | fzf --prompt="Select the worktree: " --height=40% --border
}

# Extracts the worktree path from the selected line.
# Argument 1: Full line from 'git worktree list'.
function extract_path_from_worktree() {
    local worktree_line="$1"
    echo "$worktree_line" | awk '{print $1}'
}

# Changes to the selected worktree's directory.
function change_worktree() {
    local selected_worktree
    selected_worktree=$(get_worktree)

    if [[ -n "$selected_worktree" ]]; then
        local worktree_path
        worktree_path=$(extract_path_from_worktree "$selected_worktree")
        cd "$worktree_path" && echo "Changed directory to worktree: $worktree_path"
    else
        echo "No worktree selected."
    fi
}

# Removes a selected worktree.
function remove_worktree() {
    local selected_worktree
    selected_worktree=$(get_worktree)

    if [[ -n "$selected_worktree" ]]; then
        local worktree_path
        worktree_path=$(extract_path_from_worktree "$selected_worktree")
        # The 'remove' command can fail if the worktree has modifications,
        # the '&&' ensures the success message only appears if the command succeeds.
        if git worktree remove "$worktree_path"; then
            echo "Worktree '$worktree_path' removed successfully."
        else
            die "Failed to remove worktree '$worktree_path'. Check for unsaved changes."
        fi
    else
        echo "No worktree selected."
    fi
}

# Returns the absolute path to the root directory of the Git repository.
function get_root_git_dir() {
    git rev-parse --show-toplevel
}

# Adds a new worktree.
# Argument 1: Directory name for the new worktree.
# Argument 2: Branch name to checkout.
function add_worktree() {
    local dir_name="$1"
    local branch_name="$2"
    local root_dir
    root_dir=$(get_root_git_dir)
    local worktree_path="$root_dir/.worktrees/$dir_name"

    # Check if the branch already exists locally
    if git rev-parse --verify "$branch_name" &>/dev/null; then
        echo "Creating worktree for existing branch '$branch_name'..."
        git worktree add "$worktree_path" "$branch_name"
    else
        echo "Creating new branch '$branch_name' and worktree..."
        git worktree add -b "$branch_name" "$worktree_path"
    fi
    echo "Worktree created at: $worktree_path"
}

# --- Main Function ---
function main() {
    check_dependencies

    # If no arguments are passed, execute the default action (change worktree).
    if [[ $# -eq 0 ]]; then
        check_in_git_repo
        change_worktree
        return 0
    fi

    # Process the main command.
    local command="$1"
    shift # Remove the command from the argument list

    case "$command" in
        add)
            check_in_git_repo
            if [[ $# -ne 2 ]]; then
                usage
                die "The 'add' command requires <dir-name> and <branch-name>."
            fi
            add_worktree "$1" "$2"
            ;;
        remove)
            check_in_git_repo
            remove_worktree
            ;;
        setup)
            setup_gitignore
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            usage
            die "Unknown command: '$command'"
            ;;
    esac
}

# Execute the main function with all arguments passed to the script.
main "$@"
