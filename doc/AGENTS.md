Specifications:
I want to extend the UI and state functionality:
- Each new conversation should be associated with the current working directory in Neovim (uv.cwd())
- When I press <space>gh, a "menu" should pop up with three windows: history, conversation, and prompt: the UI dimensions are already specified
- In the history window, I want to be able to display one directory per line: the top-level directory name (e.g. docs/, if not unique, then include the parent in the conflicting names) on the left side of the line, and the last modified date/time on the right
    - The shortened directory name shouldn't be 20 characters or more
- In the conversation window, I want to show the full relevant directory at the top of the window, on a single non-editable line 
    - Under this, display every message in the conversation history, neatly formatted

Can utils.generate_id() be improved?

Organize files according to design principles: isolate components, loose coupling, high cohesion

Write documentation
Write tests
