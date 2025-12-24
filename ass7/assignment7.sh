#!/bin/bash

# ===================================================================================
# Assignment 7 - Documentation and Presentation Helper Script
#
# This script provides tools to assist with the documentation and presentation
# aspects of Assignment 7.
#
# Usage:
#   ./assignment7.sh <command>
#
# Commands:
#   generate-templates  - Creates placeholder markdown files for your documentation.
#   show-checklist      - Displays the project's evaluation criteria.
#   show-submission     - Displays the final submission requirements.
#
# ===================================================================================

set -e

# --- Helper function to create a placeholder markdown file ---
create_doc_template() {
    local filename="$1"
    local title="$2"
    echo "Creating placeholder: $filename"
    cat <<EOF > "$filename"
# $title

## Overview
[Provide a high-level overview of this document's purpose.]

## Content
[Start writing your detailed content here. Use markdown formatting.]

### Sections
*   [Section 1]
*   [Section 2]

## Diagrams
[Include any relevant diagrams or code snippets.]

EOF
}

# --- Command: Generate Placeholder Documentation Templates ---
generate_templates() {
    echo "--- Generating placeholder documentation files ---"
    
    create_doc_template "Architecture_Document.md" "Project Architecture Document"
    create_doc_template "Implementation_Guide.md" "Project Implementation Guide"
    create_doc_template "Operations_Manual.md" "Project Operations Manual"
    create_doc_template "Comparison_Analysis.md" "Comparison Analysis: Linux Primitives vs Docker"

    echo "✅ Placeholder files created in the current directory."
    echo "   - Architecture_Document.md"
    echo "   - Implementation_Guide.md"
    echo "   - Operations_Manual.md"
    echo "   - Comparison_Analysis.md"
}

# --- Command: Show Evaluation Checklist ---
show_checklist() {
    echo "--- Project Evaluation Criteria ---"
    cat <<'EOF'
### Technical Implementation (40%)
- [ ] All services deployed and functional
- [ ] Correct network configuration
- [ ] Proper isolation and security
- [ ] Working service-to-service communication
- [ ] NAT and port forwarding implemented
- [ ] Monitoring and logging in place

### Code Quality (20%)
- [ ] Clean, readable code
- [ ] Proper error handling
- [ ] Configuration management
- [ ] Security best practices
- [ ] Documentation in code

### Documentation (20%)
- [ ] Comprehensive architecture document
- [ ] Clear setup instructions
- [ ] Network diagrams
- [ ] Troubleshooting guide
- [ ] Performance analysis

### Presentation (20%)
- [ ] Clear explanation of concepts
- [ ] Demonstration of working system
- [ ] Discussion of challenges
- [ ] Comparison of approaches
- [ ] Professional delivery
EOF
}

# --- Command: Show Submission Requirements ---
show_submission() {
    echo "--- Project Submission Requirements ---"
    cat <<'EOF'
1.  **Code Repository**
    - All source code
    - Configuration files
    - Scripts
    - README with setup instructions

2.  **Documentation**
    - Architecture document (PDF)
    - Implementation guide (Markdown)
    - Operations manual (PDF)
    - Comparison analysis (PDF)

3.  **Presentation Materials**
    - Slide deck (PDF/PPT)
    - Demo video (MP4)
    - Screenshots and diagrams

4.  **Test Results**
    - Performance benchmarks
    - Test logs
    - Traffic analysis
EOF
}

# --- Main script logic ---
case "$1" in
    generate-templates)
        generate_templates
        ;;
    show-checklist)
        show_checklist
        ;;
    show-submission)
        show_submission
        ;;
    *)
        echo "Usage: $0 {generate-templates|show-checklist|show-submission}"
        exit 1
        ;;
esac

exit 0
