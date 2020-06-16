// Taken from https://github.com/DataBiosphere/terra-ui/blob/6ee212abfc572d75ba6e22b788cf11730219dbff/.eslintrc.js#L4

module.exports = {
    'env': {
        'browser': true,
        'es6': true
    },
    'extends': [
        'eslint:recommended',
        'prettier',
        'plugin:react/recommended',
        'google',
        "plugin:jest/recommended"
    ],
    'globals': {
        'Atomics': 'readonly',
        'SharedArrayBuffer': 'readonly',
        '$': 'readonly',
        'jQuery': 'readonly',
        'd3': 'readonly',
        'ClassicEditor': 'readonly',
        'Spinner': 'readonly',
        'morpheus': 'readonly',
        'igv': 'readonly',
        'Ideogram': 'readonly',
        'createTracesAndLayout': 'readonly',
        'ga': 'readonly',
        'log': 'readonly',
        'bamAndBaiFiles': 'readonly'
    },
    'parser': 'babel-eslint',
    'parserOptions': {
        'ecmaFeatures': {
            'jsx': true
        },
        'ecmaVersion': 2018,
        'sourceType': 'module'
    },
    'plugins': [
        'react',
        'jsx-a11y',
        'import',
        "jest"
    ],
    'rules': {
        'array-bracket-newline': ['warn', 'consistent'],
        'array-bracket-spacing': 'warn',
        'block-spacing': 'warn',
        'brace-style': ['warn', '1tbs', { 'allowSingleLine': true }],
        'camelcase': 'warn',
        'comma-dangle': ['error', 'never'],
        'comma-spacing': 'warn',
        'comma-style': 'warn',
        'computed-property-spacing': 'warn',
        'eol-last': 'warn',
        'func-call-spacing': 'warn',
        // 'implicit-arrow-linebreak': 'warn',
        'indent': ['warn', 2, { 'SwitchCase': 1, 'CallExpression': { 'arguments': 1 } }],
        'key-spacing': 'warn',
        'keyword-spacing': 'warn',
        'lines-between-class-members': 'warn',
        'multiline-comment-style': 'off',
        'no-lonely-if': 'warn',
        'no-multi-assign': 'warn',
        'no-multiple-empty-lines': 'warn',
        'no-trailing-spaces': 'warn',
        'no-unneeded-ternary': 'warn',
        'no-whitespace-before-property': 'warn',
        'nonblock-statement-body-position': 'warn',
        'object-curly-newline': ['warn', { 'multiline': true, 'consistent': true }],
        'object-curly-spacing': ['warn', 'always'],
        'one-var': ['warn', 'never'],
        'padded-blocks': ['warn', 'never'],
        'quotes': ['warn', 'single', { 'allowTemplateLiterals': true }],
        'require-jsdoc': 'warn',
        'semi': ['warn', 'never'],
        'space-before-blocks': 'warn',
        'space-before-function-paren': ['warn', { 'anonymous': 'never', 'named': 'never', 'asyncArrow': 'always' }],
        'space-in-parens': 'warn',
        'valid-jsdoc': 'off',

        // ES6
        'arrow-parens': ['warn', 'as-needed'],
        'arrow-spacing': 'warn',
        'no-duplicate-imports': 'warn',
        'no-useless-rename': 'warn',
        'no-var': 'warn',
        'object-shorthand': 'warn',
        'prefer-arrow-callback': 'warn',
        'prefer-const': 'warn',
        'prefer-template': 'warn',
        'prefer-rest-params': 'warn',
        'prefer-spread': 'warn',
        'rest-spread-spacing': 'warn',
        'template-curly-spacing': 'warn',
        // React
        'react/prop-types': 'off',
        'react/jsx-key': 'off',
         //Jest
         "jest/no-disabled-tests": "warn",
         // remove .only from your tests whenever you are using the exclusivity feature
         // so test can be executed on build system
         "jest/no-focused-tests": "error",
         "jest/no-identical-title": "error",
         //Reminds should be used upon asserting expectations on object's length property
         "jest/prefer-to-have-length": "warn",
    }
};
