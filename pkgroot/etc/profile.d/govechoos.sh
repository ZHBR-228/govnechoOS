# govechoOS: фирменные алиасы и подсказки (MIT, автор ZHBR-228)
alias gov='govctl'
alias gstat='govctl status'
alias gapps='govctl apps list'
alias gtidy='govclean apply'
alias gecho='govecho -s banner'
[ -f /etc/issue ] && [ "$PS1" ] && grep -q govechoOS /etc/os-release 2>/dev/null && \
    echo "Совет: наберите 'govctl' — консоль управления govechoOS (автор: ZHBR-228)"
